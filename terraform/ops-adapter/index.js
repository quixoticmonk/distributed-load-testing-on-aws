// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
//
// Terraform lifecycle adapter for Distributed Load Testing on AWS.
//
// The upstream custom-resource Lambda (source/custom-resource/main-index.js) speaks the
// CloudFormation custom-resource protocol: it PUTs its result to event.ResponseURL and
// throws when that URL is absent. Terraform has no ResponseURL, so this adapter reuses
// the same upstream libraries and returns a plain JSON result instead.
//
// Two Terraform callers use it:
//
//   1. Terraform actions (action "aws_lambda_invoke") fired by action_trigger on
//      after_create / after_update. Payload: { "operation": "<name>", ... }.
//
//   2. aws_lambda_invocation with lifecycle_scope = "CRUD" for destroy-time work,
//      because action_trigger has no before_destroy / after_destroy event.
//      The provider adds { "tf": { "action": "create" | "update" | "delete", ... } }.
//      Destroy-only operations do nothing unless tf.action is "delete".

const scenarios = require("../../source/custom-resource/lib/scenarios");
const iot = require("../../source/custom-resource/lib/iot");

// Operations that only make sense when the hub is being torn down.
const DESTROY_ONLY = new Set(["cleanup-test-scenarios", "detach-iot-policy"]);

const operations = {
  // Deletes EventBridge Scheduler schedules that test scenarios created outside Terraform.
  "cleanup-test-scenarios": async () => scenarios.cleanUpTestScenarioResources(),

  // Detaches every Cognito identity principal from the IoT policy so Terraform can delete it.
  "detach-iot-policy": async (event) => {
    if (!event.iotPolicyName) {
      throw new Error("detach-iot-policy requires iotPolicyName");
    }
    return iot.detachIotPolicy(event.iotPolicyName);
  },

  // Fills totalTestRuns on scenarios that predate the counter. No-op on a fresh hub.
  "backfill-test-run-counts": async () => scenarios.backfillTestRunCounts(),
};

exports.handler = async (event) => {
  const operation = event?.operation;
  const tfAction = event?.tf?.action;

  console.log(JSON.stringify({ logEvent: "TF_OPS_ADAPTER", operation, tfAction }));

  const run = operations[operation];
  if (!run) {
    throw new Error(`Unsupported operation: ${operation}`);
  }

  if (DESTROY_ONLY.has(operation) && tfAction !== "delete") {
    return { operation, status: "skipped", reason: `runs on delete only (tf.action=${tfAction ?? "none"})` };
  }

  const result = await run(event);
  return { operation, status: "success", result: result ?? null };
};
