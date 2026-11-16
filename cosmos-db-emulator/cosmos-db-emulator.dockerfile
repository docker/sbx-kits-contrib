# syntax=docker/dockerfile:1
# The cosmos-db-emulator overlay: the helper the startup hook runs, the
# emulator's account key, and a profile.d drop-in that derives the endpoint and
# connection string at shell start. No build stage, so publishing pulls
# nothing: the emulator itself is an image the in-sandbox Docker daemon pulls
# at boot.
FROM scratch

# The source keeps a `.sh` suffix so .gitattributes' `*.sh text eol=lf` holds
# it to LF on every checkout -- a CRLF shebang does not run -- and it lands
# without one, under the command name the README and agent context use.
COPY --chmod=0755 files/usr/local/bin/cosmos-emulator.sh /usr/local/bin/cosmos-emulator

# The emulator's documented, publicly known account key -- not a secret. The
# vNext emulator does not check it at all, but every SDK wants a key to sign
# requests with, and this is the one Microsoft's docs and samples use. Image
# ENV, because only this kit sets it, so the env merge cannot conflict, and so
# it reaches every process rather than only login shells.
ENV COSMOS_EMULATOR_KEY="C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw=="

# What depends on the `protocol` arg cannot be image ENV -- the arg is chosen
# when the sandbox is created, long after this overlay was built -- so login
# shells derive it here. NO_PROXY is appended to rather than set, because the
# base may set it too, and SDK traffic to the emulator must not leave through
# the sandbox's proxy. Each host is added once, so a nested login shell does
# not grow the list.
COPY <<'EOF' /etc/profile.d/cosmos-db-emulator-env.sh
export COSMOS_EMULATOR_ENDPOINT="${COSMOS_EMULATOR_PROTOCOL:-http}://localhost:8081/"
export COSMOS_EMULATOR_CONNECTION_STRING="AccountEndpoint=${COSMOS_EMULATOR_ENDPOINT};AccountKey=${COSMOS_EMULATOR_KEY:-};"
for _cosmos_host in localhost 127.0.0.1; do
  case ",${NO_PROXY:-}," in
    *",$_cosmos_host,"*) ;;
    *) NO_PROXY="${NO_PROXY:+$NO_PROXY,}$_cosmos_host" ;;
  esac
done
unset _cosmos_host
export NO_PROXY
export no_proxy="$NO_PROXY"
EOF
