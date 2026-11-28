"""The unit of work applies the actor, rolls back by default and never leaks it."""

from __future__ import annotations

from uuid import uuid4

from mavrykx.domain.actor import Actor
from mavrykx.infrastructure.unit_of_work import SqlAlchemyUnitOfWork, actor_parameters


class RecordingSession:
    """A session double that records what the unit of work asks of it."""

    def __init__(self) -> None:
        self.statements: list[tuple[str, dict[str, str]]] = []
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    async def execute(self, statement: object, parameters: dict[str, str] | None = None) -> None:
        self.statements.append((str(statement), dict(parameters or {})))

    async def commit(self) -> None:
        self.commits += 1

    async def rollback(self) -> None:
        self.rollbacks += 1

    async def close(self) -> None:
        self.closed = True


def factory(session: RecordingSession) -> object:
    return lambda: session


def test_actor_parameters_render_a_user() -> None:
    user_id = uuid4()
    assert actor_parameters(Actor(user_id=user_id)) == {"user_id": str(user_id)}


def test_actor_parameters_are_empty_for_an_installation() -> None:
    assert actor_parameters(Actor()) == {"user_id": ""}


async def test_entering_applies_the_actor_as_a_transaction_local_setting() -> None:
    session = RecordingSession()
    user_id = uuid4()

    async with SqlAlchemyUnitOfWork(factory(session), Actor(user_id=user_id)) as unit:  # type: ignore[arg-type]
        assert unit.actor.user_id == user_id
        assert unit.session is session

    statement, parameters = session.statements[0]
    assert "set_config" in statement
    assert parameters == {"setting": "app.user_id", "value": str(user_id)}


async def test_leaving_without_a_commit_rolls_back_and_closes() -> None:
    session = RecordingSession()

    async with SqlAlchemyUnitOfWork(factory(session), Actor()):  # type: ignore[arg-type]
        pass

    assert session.commits == 0
    assert session.rollbacks == 1
    assert session.closed is True


async def test_a_committed_unit_is_still_rolled_back_on_close() -> None:
    session = RecordingSession()

    async with SqlAlchemyUnitOfWork(factory(session), Actor()) as unit:  # type: ignore[arg-type]
        await unit.commit()

    assert session.commits == 1
    assert session.rollbacks == 1
    assert session.closed is True


async def test_each_unit_opens_its_own_session() -> None:
    first = RecordingSession()
    second = RecordingSession()
    actor = Actor(user_id=uuid4())

    async with SqlAlchemyUnitOfWork(factory(first), actor):  # type: ignore[arg-type]
        pass
    async with SqlAlchemyUnitOfWork(factory(second), actor):  # type: ignore[arg-type]
        pass

    assert len(first.statements) == 1
    assert len(second.statements) == 1
