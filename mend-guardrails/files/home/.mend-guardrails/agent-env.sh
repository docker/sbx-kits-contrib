# Sourced by login/interactive shells. Do not set HTTP(S)_PROXY here.
# Loopback must bypass the sbx proxy or /health and /v1/guard/* get 403.
_mend_guardrails_append_noproxy() {
  _var=$1
  _host=$2
  eval "_val=\${${_var}:-}"
  case ",${_val}," in
    *,${_host},*) ;;
    *)
      if [ -n "${_val}" ]; then
        export "${_var}=${_val},${_host}"
      else
        export "${_var}=${_host}"
      fi
      ;;
  esac
  unset _var _host _val
}

for _h in api.openai.com 127.0.0.1 localhost ::1; do
  _mend_guardrails_append_noproxy NO_PROXY "$_h"
  _mend_guardrails_append_noproxy no_proxy "$_h"
done
unset _h

# Codex provider env_key=OPENAI_API_KEY. Docker sentinel — host proxy swaps the
# real key on upstream after Guardrails forwards Authorization.
if [ -z "${OPENAI_API_KEY:-}" ]; then
  export OPENAI_API_KEY="proxy-managed"
fi
