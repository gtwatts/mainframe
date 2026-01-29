"""Bash execution engine for running MAINFRAME functions."""

import subprocess
import os
import shlex
from typing import Dict, Any, Optional, Tuple

class BashExecutor:
    """Executes MAINFRAME bash functions via subprocess."""

    def __init__(self, mainframe_root: Optional[str] = None):
        self.mainframe_root = mainframe_root or os.environ.get(
            'MAINFRAME_ROOT',
            os.path.expanduser('~/.mainframe')
        )
        self.common_sh = os.path.join(self.mainframe_root, 'lib', 'common.sh')
        self.timeout = 30  # Default timeout in seconds

    def execute(self, func_name: str, args: Dict[str, Any]) -> Tuple[bool, str, str]:
        """Execute a MAINFRAME function.

        Args:
            func_name: Name of the function to call
            args: Arguments to pass (either named params or 'args' list)

        Returns:
            Tuple of (success, stdout, stderr)
        """
        # Build bash command
        if 'args' in args and isinstance(args['args'], list):
            # Variadic arguments
            quoted_args = ' '.join(shlex.quote(str(a)) for a in args['args'])
            func_call = f'{func_name} {quoted_args}'
        else:
            # Named parameters - convert to positional
            arg_values = []
            for _, value in args.items():
                if value is not None:
                    arg_values.append(shlex.quote(str(value)))
            func_call = f'{func_name} {" ".join(arg_values)}'

        # Build full bash script
        bash_script = f'''
            source "{self.common_sh}" 2>/dev/null || true
            export MAINFRAME_OUTPUT=json
            {func_call}
        '''

        try:
            env = os.environ.copy()
            env['MAINFRAME_ROOT'] = self.mainframe_root

            result = subprocess.run(
                ['bash', '-c', bash_script],
                capture_output=True,
                text=True,
                timeout=self.timeout,
                env=env
            )

            success = result.returncode == 0
            return success, result.stdout, result.stderr

        except subprocess.TimeoutExpired:
            return False, '', f'Function {func_name} timed out after {self.timeout}s'
        except Exception as e:
            return False, '', f'Execution error: {str(e)}'
