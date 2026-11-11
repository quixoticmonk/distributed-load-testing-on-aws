# Distributed Load Testing on AWS: Terraform

Terraform port of [Distributed Load Testing on AWS](https://docs.aws.amazon.com/solutions/distributed-load-testing-on-aws/) v4.3.5 (upstream is AWS CDK in TypeScript). This folder sits inside the upstream repository, next to `source/` and `deployment/`. The application code (Lambdas, web console, load-tester images) is built unmodified from `../source`. Only the infrastructure is re-expressed.

## Modules

```
modules/
├── dlt-hub            composition: wires everything below, plus lifecycle hooks and metadata shim
├── dlt-storage        scenarios + access-log buckets, 4 DynamoDB tables, JMeter bundle
├── dlt-load-runner    VPC (optional), ECS cluster, task roles, log group, real-time publisher
├── dlt-orchestration  13 worker Lambdas, Step Functions state machine, EventBridge rules, alarm
├── dlt-api            REST API (OpenAPI body), api-services Lambda, scheduler role
├── dlt-auth           Cognito user pool / client / domain / identity pool, IoT policy
├── dlt-console        S3 + CloudFront console, CSP, assets, aws-exports.json
├── dlt-mcp            optional AgentCore Gateway MCP server
└── dlt-region         spoke region: dlt-load-runner + registration in the hub
```

Each leaf module has one owner concern and can be versioned independently. `dlt-hub` is the only module that knows how they connect. A spoke region is one `dlt-region` block with its own provider. Spokes do not need a CloudFormation template.

## Prerequisites

* Terraform >= 1.14 (actions). Tested with 1.16.0-alpha20260513 and hashicorp/aws 6.72.0.
* Node.js and npm (upstream pins node >= 24; bundles target node24 either way), `zip`, `curl`, `jq`.
* Run from this folder inside the upstream repo (`UPSTREAM` defaults to `..`).

## Usage

```bash
cd terraform
make build                                   # Lambda zips, web console, JMeter bundle -> ./build
cp examples/complete/terraform.tfvars.example examples/complete/terraform.tfvars
make plan                                    # builds first if needed, saves examples/complete/tfplan
make apply                                   # applies only the saved plan; refuses a missing or stale one
make destroy                                 # rebuilds artifacts (destroy reads their hashes), then prompts
```

Other targets: `make fmt`, `make validate`, `make lint` (tflint), `make scan` (checkov), `make test` (mocked, no AWS). `make help` lists everything. `validate`, `lint` and `test` stop at the first failing directory and exit non-zero. npm dependencies reinstall automatically when an upstream `package-lock.json` changes. The stamp is `build/.deps-installed`.

## Custom resources: what replaced them

| Upstream custom resource | Terraform |
|---|---|
| UUID | `random_uuid` |
| GetIotEndpoint | `data.aws_iot_endpoint` |
| TestingResourcesConfigFile (hub + regional) | `aws_dynamodb_table_item` `region-<region>` |
| ConsoleConfig / aws-exports | `aws_s3_object` from `runtime_config` |
| BucketDeployment (web console) | `aws_s3_object` for_each + `action "aws_cloudfront_create_invalidation"` |
| UpdateCsp | CSP computed at plan time (Cognito domain is derived from the UUID) |
| CognitoUICustomization | `aws_cognito_user_pool_ui_customization` |
| CopyJMeterBundle | `aws_s3_object` (bundle built by `make jmeter`) |
| PutRegionalTemplate | not needed: regions use `dlt-region` |
| BackfillTestRunCounts | `action "aws_lambda_invoke"` on `after_create`/`after_update` |
| CleanUpTestScenarios (delete) | `aws_lambda_invocation` with `lifecycle_scope = "CRUD"` |
| DetachIotPolicy (delete) | `aws_lambda_invocation` with `lifecycle_scope = "CRUD"` |
| V3toV4BackCompat | dropped (in-place upgrade from v3 stacks only) |
| Metric (anonymous usage) | dropped |

`action_trigger` supports only `before_create`, `after_create`, `before_update` and `after_update`. Terraform 1.16.0-alpha rejects `before_destroy`. Delete-time work therefore goes through `aws_lambda_invocation`, which re-invokes the function with `tf.action = "delete"` on destroy. Both paths call `ops-adapter/index.js`, a thin wrapper over the upstream `custom-resource/lib/*` modules. The upstream handler can't be called directly because it PUTs to a CloudFormation `ResponseURL` and throws without one.

## Deliberate differences from upstream

* **Metadata shim stack** (`dlt-hub/metadata.tf`). The API reads CloudFormation at runtime. `/stack-info` calls `DescribeStacks` and `/regions` calls `ListExports`, and `/regions` throws without the `<stack>-RegionalCFTemplate` export. A one-resource stack (`WaitConditionHandle`) provides the outputs, export and `SolutionVersion` tag, so the app code runs unmodified.
* **IAM**: Lambda log writes are scoped to each function's own log group, where upstream grants `/aws/lambda/*`. The non-existent `s3:HeadObject` action is dropped.
* **OAuth callbacks**: upstream hardcodes localhost and third-party MCP client callbacks (claude.ai, cursor.com, vscode.dev). Here they're opt-in via `oauth_additional_callback_urls`.
* **API Gateway account role**: upstream sets the account-wide CloudWatch role twice. Here it's a single resource behind `manage_api_gateway_account`.
* **Access logs** expire after `access_log_retention_in_days` (365). Upstream keeps them forever.
* **Not ported**: the ALB + ECS console variant (use `console_mode = "headless"` and host the console yourself), the weekly AWS-metrics Lambda/SQS pipeline, and the 13 billed-duration saved queries that only feed it.
* `solution_metrics_url` defaults to the AWS endpoint, because the Lambdas require `METRIC_URL`. Point it at an internal sink to stop outbound calls.

## Validation status

| Check | Result |
|---|---|
| Lambda bundles vs CDK synth (16 functions) | Same code; only esbuild module-path comments/IDs differ |
| `terraform validate` (8 modules + example) | Pass |
| `terraform fmt -check`, tflint | Clean |
| `terraform test` (mocked plan + apply, 6 runs) | Pass: hub + spoke, headless + MCP, custom-resource replacements, CSP, orchestration wiring |
| checkov | 757 passed / 144 failed; failures are baseline choices listed below, not regressions |
| Real AWS apply + smoke test | **Not run yet** (no AWS credentials in this session) |

Checkov failures not addressed: CloudWatch log groups without a CMK, Lambdas outside a VPC and without DLQs, code signing, or reserved concurrency; CloudFront using the default certificate (TLS 1.0 minimum) without WAF; S3 without replication. Each is a platform-baseline decision.

## Known runtime constraints (from upstream code)

* `task-runner` launches tasks with `assignPublicIp: ENABLED` (`source/task-runner/src/service.ts`). An SCP or Config rule that denies public IPs on ENIs will break tests.
* IAM policies in the app are scoped by the tag `SolutionId = SO0062`. Don't change `solution_id`.
* The console's authenticated role allows `iot:AttachPolicy` on `*` (upstream).
