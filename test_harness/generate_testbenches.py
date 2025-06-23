r"""Script creates dummy testbenches for each problem in the specified folder.

Run for visible problems:
python test_harness/generate_testbenches.py \
  --problems_folder="${PWD}/visible_problems"

Run for hidden problems:
python test_harness/generate_testbenches.py \
  --problems_folder="${PWD}/hidden_problems"
"""

from collections.abc import Sequence
import pathlib

from absl import app
from absl import flags
from wrapt_timeout_decorator import timeout

import agent
import constants


_PROBLEMS_FOLDER = flags.DEFINE_string(
    "problems_folder",
    None,
    "The path to the problems folder.",
    required=True,
)
_TESTBENCH_GENERATION_TIMEOUT_SECONDS = 15 * 60


def main(argv: Sequence[str]) -> None:
    if len(argv) > 1:
        raise app.UsageError("Too many command-line arguments.")
    problems_folder = pathlib.Path(_PROBLEMS_FOLDER.value)
    if not problems_folder.is_dir():
        raise ValueError(
            f"Problems folder {problems_folder} does not exist or is not a directory."
        )

    module_names = [f.name for f in problems_folder.iterdir() if f.is_dir()]
    agent_with_timeout = timeout(_TESTBENCH_GENERATION_TIMEOUT_SECONDS)(
        agent.generate_testbench
    )
    for module in module_names:
        problem_dir = problems_folder / module
        files_dict = {}
        for file in problem_dir.iterdir():
            if file.is_file():
                files_dict[file.name] = file.read_text()
        try:
            testbench = agent_with_timeout(files_dict)
        except TimeoutError:
            print(
                f"Timeout while generating testbench for {module}, using dummy testbench."
            )
            testbench = constants.DUMMY_TESTBENCH
        testbench_file = problem_dir / constants.TESTBENCH_FILE_NAME
        testbench_file.write_text(testbench)


if __name__ == "__main__":
    app.run(main)
