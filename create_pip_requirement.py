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

def create_pip_requirement(remove_versions=True):
    version = f"{sys.version_info.major}.{sys.version_info.minor}"
    env_name = get_env_name()

    # Get parent of current script directory
    script_path = Path(__file__).resolve()
    parent_dir = script_path.parent
    requirements_dir = parent_dir / "requirements"
    requirements_dir.mkdir(parents=True, exist_ok=True)

    # File path for requirements
    filename = f"{env_name}-python-{version}.txt"
    filepath = requirements_dir / filename

    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "freeze", "-l"],
            capture_output=True, text=True, check=True
        )

        # Filter out lines with '-e' (editable installs)
        filtered_output = "\n".join(
            line for line in result.stdout.splitlines() 
            if not line.startswith("-e")
        )

        if remove_versions:
            # Remove package versions by splitting at '=='
            filtered_output = "\n".join(
                line.split("==")[0] 
                for line in filtered_output.splitlines()
            )

        # Write the output to the file
        with open(filepath, "w") as f:
            f.write(filtered_output)

        print(f"Requirements saved to {filepath}")
    except subprocess.CalledProcessError as e:
        print("Failed to generate requirements:", e)

if __name__ == "__main__":
    create_pip_requirement()
