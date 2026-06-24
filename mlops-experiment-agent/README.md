# MLOps Experiment Agent Kit

> A Docker SBX mixin kit that automatically configures an MLflow tracking server inside a sandbox, enabling Claude Code to orchestrate ML experiments, log metrics, version models, and manage datasets — all in an isolated and reproducible environment.

## Purpose & Objective

Machine learning experimentation is messy by nature: you run dozens of iterations, tweak hyperparameters, compare models, and lose track of what worked. This kit solves that by giving Claude Code a fully configured MLflow backend the moment the sandbox starts — no manual setup, no configuration drift, no lost experiments.

**This kit is ideal for:**
- CV and image classification pipelines (YOLO, EfficientNet, DINOv2)
- Rapid prototyping of ML models with experiment tracking
- Teams that want reproducible, versioned ML experiments inside ephemeral sandboxes
- MLOps workflows where logging, metrics, and model registry matter from day one

## What Kind of Kit Is This?

We chose `kind: mixin` because the goal is to **augment Claude Code** with MLflow capabilities, not replace it. Claude Code remains the agent; this kit layers the MLflow infrastructure on top.

## Kit Structure

```
mlops-experiment-agent/
├── spec.yaml # Kit manifest (the heart of the kit)
├── Dockerfile # Base image with heavy ML dependencies
├── CLAUDE.md # Instructions for the Claude Code agent
├── scripts/
│   └── start-mlflow.sh
└── README.md # This file
```

### Rule of thumb (from Oleg's learnings)
> **The Docker image** -> heavy, stable dependencies (Python, MLflow, scikit-learn)
>
> **The kit YAML** -> what changes often: credentials, network rules, startup commands, env vars


## spec.yaml

```yaml
schemaVersion: "1"
kind: mixin
name: mlops-mixin
displayName: MLOps Experiment Agent
description: >
  Orchestrates ML experiments inside a Docker Sandbox. Tracks runs,
  logs metrics and parameters, versions models using MLflow.
  Ideal for classification and CV pipelines.

environment:
  variables:
    MLFLOW_TRACKING_URI: "http://localhost:5000"
    MLFLOW_EXPERIMENT_NAME: "sandbox-experiments"

network:
  allowedDomains:
    - "pypi.org:443"
    - "files.pythonhosted.org:443"

commands:
  install:
    - command: "pip install --break-system-packages --upgrade pip && pip install --break-system-packages 'numpy>=2.0' 'pandas>=2.0' 'scikit-learn>=1.5' 'mlflow>=2.13' boto3 && sed -i 's/from importlib.abc import Traversable/from importlib.resources.abc import Traversable/' /home/agent/.local/lib/python3.14/site-packages/mlflow/assistant/skill_installer.py"
      user: "1000"
      description: "Install MLflow and ML dependencies and patch Python 3.14 compatibility"
  startup:
    - command: ["sh", "-c", "mkdir -p /home/agent/.mlflow/artifacts && setsid /home/agent/.local/bin/mlflow server --backend-store-uri sqlite:////home/agent/.mlflow/mlflow.db --default-artifact-root /home/agent/.mlflow/artifacts --host 0.0.0.0 --port 5000 > /home/agent/.mlflow/server.log 2>&1 &"]
      user: "1000"
      description: "Start MLflow tracking server"
```


## Usage

### Run the sandbox

```bash
sbx run \
  --kit docker.io/yharyarias/mlops-experiment-agent-kit:latest \
  --name mlops-sandbox \
  claude
```

### Access the MLflow UI from your host machine

```bash
sbx ports mlops-sandbox --publish 5000:5000/tcp
```

Then open: [http://localhost:5000](http://localhost:5000)

### Example prompts for Claude Code inside the sandbox

```
Run a baseline logistic regression experiment on the iris dataset and log the results to MLflow
```
```
Compare the last 3 MLflow runs by accuracy and tell me which model performed best
```
```
Register the best model to the MLflow Model Registry
```
```
Show me all experiments logged today
```

## Known Issues & How We Solved Them

### 1. Python 3.14 incompatibility with NumPy

**Error:**
```
ERROR: Cannot compile `Python.h`. Perhaps you need to install python-dev|python-devel
Preparing metadata (pyproject.toml) did not run successfully.
```

**Root cause:** The sandbox base image uses Python 3.14. NumPy versions below 2.0 do not have prebuilt wheels for Python 3.14 and attempt to compile from source, failing because build tools or Python headers are missing.

**Solution:** Use `numpy>=2.0`, `pandas>=2.0`, and `scikit-learn>=1.5` which have prebuilt wheels for Python 3.14/aarch64.

```bash
pip install --break-system-packages 'numpy>=2.0' 'pandas>=2.0' 'scikit-learn>=1.5' 'mlflow>=2.13' boto3
```

### 2. MLflow ImportError on Python 3.14

**Error:**
```
ImportError: cannot import name 'Traversable' from 'importlib.abc'
```

**Root cause:** `importlib.abc.Traversable` was removed in Python 3.14 and moved to `importlib.resources.abc`. MLflow's `skill_installer.py` uses the old import path.

**Solution:** Apply a `sed` patch automatically during the install hook:

```bash
sed -i 's/from importlib.abc import Traversable/from importlib.resources.abc import Traversable/' \
  /home/agent/.local/lib/python3.14/site-packages/mlflow/assistant/skill_installer.py
```

### 3. Background process dies during startup

**Error:**
```
setsid: failed to execute mlflow: No such file or directory
```

**Root cause:** Two issues combined:
- The `PATH` is not set during startup hooks, so `mlflow` is not found
- Background processes started without `setsid` die when the startup session ends

**Solution:** Use the **absolute path** for the binary and always prefix background processes with `setsid`:

```bash
# Wrong
mlflow server ...

# Correct
setsid /home/agent/.local/bin/mlflow server ...
```

> This is documented in Oleg Selajev's learnings: *"Use absolute binary paths and run detached sessions via `setsid` to ensure background processes survive the startup hook."*

### 4. aarch64 platform mismatch on Apple Silicon

**Error:**
```
no match for platform in manifest: not found
```

**Root cause:** Building a Docker image on Mac Apple Silicon (M1/M2/M3) produces an `aarch64` image by default. The sbx sandbox expects a multi-arch image.

**Solution:** Use `docker buildx` to build and push a multi-arch image:

```bash
docker buildx create --name multiarch-builder --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t yharyarias/mlops-experiment-agent:latest \
  --push .
```

## Recommendations

- **Keep kits narrow:** This kit only installs what MLflow needs. Avoid bundling unrelated tools — narrower kits are more secure and composable.
- **Use `setsid` + absolute paths** for any background process in a startup hook.
- **Always test the install command locally** using the hint Docker provides on failure:
  ```bash
  docker run --rm -u '1000' 'docker/sandbox-templates:claude-code-docker' sh -c 'your install command'
  ```
- **Stage before pushing:** `sbx kit push` does not respect `.gitignore`. Always use `rsync` with excludes to avoid leaking `.env` or `.venv` files.
- **Verify your startup logs:**
  ```bash
  sbx exec <sandbox-name> -- cat /var/log/sbx-kit-startup.log
  sbx exec <sandbox-name> -- cat /home/agent/.mlflow/server.log
  ```

## Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `MLFLOW_TRACKING_URI` | `http://localhost:5000` | MLflow server endpoint used by the agent |
| `MLFLOW_EXPERIMENT_NAME` | `sandbox-experiments` | Default experiment name for new runs |


## Author

**Yhary Arias** — Docker Captain, AI Engineer  
[@ai.fania](https://www.instagram.com/ai.fania) · [LinkedIn](https://linkedin.com/in/yharyarias)

Built as part of the Docker Captains SBX Kit community activity led by Eva Bojorges.