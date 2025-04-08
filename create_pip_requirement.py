import subprocess
import sys
import os
from pathlib import Path

def get_env_name():
    venv_path = os.environ.get("VIRTUAL_ENV")
    conda_env = os.environ.get("CONDA_DEFAULT_ENV")

    if venv_path:
        return Path(venv_path).name
    elif conda_env:
        return conda_env
    else:
        return "global"

def create_pip_requirement():
    version = f"{sys.version_info.major}.{sys.version_info.minor}"
    env_name = get_env_name()

    # Get parent of current script directory
    script_path = Path(__file__).resolve()
    parent_dir = script_path.parent

    # Ensure requirements directory exists
    requirements_dir = parent_dir / "requirements"
    requirements_dir.mkdir(parents=True, exist_ok=True)

    # File path for requirements
    filename = f"{env_name}-python-{version}.txt"
    filepath = requirements_dir / filename

    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "list", "--format=freeze"],
            capture_output=True, text=True, check=True
        )

        with open(filepath, "w") as f:
            f.write(result.stdout)

        print(f"Requirements saved to {filepath}")
    except subprocess.CalledProcessError as e:
        print("Failed to generate requirements:", e)

if __name__ == "__main__":
    create_pip_requirement()
