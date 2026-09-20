## Multi-architecture emulation (QEMU / binfmt)

QEMU user-mode emulators are registered with the kernel's binfmt_misc, so
this sandbox can run and build container images for non-native CPU
architectures (e.g. linux/arm64 on an amd64 host and vice versa).

- Run a foreign-arch image directly:
  `docker run --rm --platform linux/arm64 alpine uname -m`
- Build multi-arch images with buildx:
  `docker buildx build --platform linux/amd64,linux/arm64 .`
- Check which emulators are registered:
  `docker run --privileged --rm tonistiigi/binfmt` prints them as JSON.
  `ls /proc/sys/fs/binfmt_misc/qemu-*` only works when binfmt_misc happens
  to be mounted in the sandbox, so an empty or missing directory does not
  mean emulation is unavailable — confirm with the `uname -m` command above.
- If emulation is missing, read the startup log
  (`cat /var/log/sbx-kit-startup.log`) and re-run the registration:
  `docker run --privileged --rm tonistiigi/binfmt --install all`
