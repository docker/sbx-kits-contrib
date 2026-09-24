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

## Recommendations

- **Keep kits narrow:** This kit only installs what MLflow needs. Avoid bundling unrelated tools, narrower kits are more secure and composable.
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

`MLFLOW_TRACKING_URI` - `http://localhost:5000` - MLflow server endpoint used by the agent |
`MLFLOW_EXPERIMENT_NAME` - `sandbox-experiments` - Default experiment name for new runs |


## Author

**Yhary Arias** - Docker Captain, AI Engineer