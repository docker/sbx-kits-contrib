# devin

[Devin CLI](https://docs.devin.ai/cli) by Cognition as a Docker Sandboxes kit.

## Usage

```console
sbx run --kit "docker.io/sbx/devin-kit:latest" devin
```

To run it from a local clone:

```console
sbx run --kit ./devin devin
```

Devin prompts for login on first launch. Its credential remains in that
sandbox and is not added to the sbx secret store, so every new sandbox requires
another login.

## Local image

The image must be loaded into sbx's image store before testing an unpublished
local build:

```console
docker build -t docker.io/sbx/devin-image:latest ./devin
docker save docker.io/sbx/devin-image:latest -o /tmp/devin-image.tar
sbx template load /tmp/devin-image.tar
rm /tmp/devin-image.tar
```
