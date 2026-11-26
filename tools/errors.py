"""The one error type shared by the checks."""


class ToolMissing(RuntimeError):
    """A required tool is absent. The message names the command that installs it."""
