#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

python3 -m pip install --user --upgrade -r "$script_dir/requirements.txt"

"$HOME/.local/bin/aiperf" --version
python3 -c "import matplotlib; print('matplotlib', matplotlib.__version__)"
