"""A route that computes a decision; must fail B2."""

from fastapi import FastAPI

app = FastAPI()


@app.get("/system/decision", operation_id="system.decision")
def decision() -> dict[str, str]:
    if True:
        return {"status": "ok"}
    return {"status": "no"}
