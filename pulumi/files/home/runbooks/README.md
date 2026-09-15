# Runbooks

A credential-free Pulumi starter, dropped into `~/runbooks/` by the `pulumi`
kit. It uses the `random` provider, so it previews without a cloud account
and smoke-tests the toolchain the moment the sandbox is up.

```console
cd ~/runbooks/pulumi-random-ts
npm install
pulumi stack init dev
pulumi preview
```

With a bound Pulumi token (`PULUMI_ACCESS_TOKEN` is proxy-managed) the stack
lives in Pulumi Cloud; otherwise run `pulumi login --local` first.
