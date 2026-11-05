## Google Cloud CLI authentication

This kit authenticates gcloud through the host proxy. When configured,
CLOUDSDK_AUTH_ACCESS_TOKEN contains a placeholder. An empty `gcloud auth list`
and missing ADC are expected: neither proves that API access is unavailable.
Try a read-only operation with an explicit project before diagnosing access.
Do not run `gcloud auth login` or `gcloud auth application-default login` inside
the sandbox, copy host credentials, request service-account keys, or print tokens.
If the credential is unbound, ask the operator to configure the host secret.

The kit covers Resource Manager, Compute, Storage, the global Cloud Run API,
and one regional Cloud Run endpoint selected by the `run_region` kit argument
(default us-central1, exported as CLOUDSDK_RUN_REGION). Use that region for
Cloud Run commands. A different --region may use an endpoint outside credential
injection and fail with CREDENTIALS_MISSING even while other API calls succeed.
That is a domain coverage problem, not a reason to log in inside the sandbox.

IAM, Cloud SQL, and other APIs need their exact API hosts added to the network
allow list, credential injection list, and host binding. Do not assume all Google
APIs are authenticated. Report the specific missing API or region. IAM permissions
still apply; access is not inherently read-only. Avoid HTTP auth-header logging.
