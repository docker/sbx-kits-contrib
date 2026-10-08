set -eu

MLFLOW_DIR="${HOME}/.mlflow"
mkdir -p "${MLFLOW_DIR}/artifacts"

if ! pgrep -f "mlflow server" > /dev/null 2>&1; then
  setsid mlflow server \
    --backend-store-uri "sqlite:///${MLFLOW_DIR}/mlflow.db" \
    --default-artifact-root "${MLFLOW_DIR}/artifacts" \
    --host 0.0.0.0 \
    --port 5000 \
    > "${MLFLOW_DIR}/server.log" 2>&1 &
  echo "MLflow server started at http://localhost:5000"
else
  echo "MLflow server already running"
fi