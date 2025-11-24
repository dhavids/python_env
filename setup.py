from setuptools import setup, find_packages
from pathlib import Path
import os

# This setup.py will be copied to the base folder (e.g., argos)
# It dynamically determines the folder name for the package

# Get the directory where this setup.py is located
setup_dir = Path(__file__).parent.resolve()
folder_name = setup_dir.name

# Use the folder name as the package name (e.g., "argos")
package_name = folder_name.lower()

setup(
    name=package_name,
    version="1.0",
    description=f"Local development setup for {folder_name}",
    author="mod by Ayomide Agunloye",
    packages=find_packages(),
    zip_safe=False,
)