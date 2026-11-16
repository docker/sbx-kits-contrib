## Claude Code on Amazon Bedrock

This sandbox sends Claude Code's model calls to Amazon Bedrock
(`CLAUDE_CODE_USE_BEDROCK=1`), using the AWS profile stored on the host under
the `bedrock` credential. The default Sonnet model is
`us.anthropic.claude-sonnet-4-5-20250929-v1:0`.

Credentials are short-lived. A sidecar refreshes
`~/.aws/sbx-bedrock-credentials.json` in place before expiry, and Claude Code
re-reads it through the `awsCredentialExport` setting. Do not copy the values
elsewhere or write them to `~/.aws/credentials`.

Egress is limited to `bedrock-runtime.*.amazonaws.com` and
`bedrock.*.amazonaws.com`. Other AWS services, including STS and S3, are not
reachable.
