from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GenerateReportRequest(_message.Message):
    __slots__ = ("user_id", "instructions", "data", "context")
    USER_ID_FIELD_NUMBER: _ClassVar[int]
    INSTRUCTIONS_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_FIELD_NUMBER: _ClassVar[int]
    user_id: str
    instructions: str
    data: str
    context: str
    def __init__(self, user_id: _Optional[str] = ..., instructions: _Optional[str] = ..., data: _Optional[str] = ..., context: _Optional[str] = ...) -> None: ...

class GenerateReportResponse(_message.Message):
    __slots__ = ("tasks", "thinking", "report")
    TASKS_FIELD_NUMBER: _ClassVar[int]
    THINKING_FIELD_NUMBER: _ClassVar[int]
    REPORT_FIELD_NUMBER: _ClassVar[int]
    tasks: str
    thinking: str
    report: Report
    def __init__(self, tasks: _Optional[str] = ..., thinking: _Optional[str] = ..., report: _Optional[_Union[Report, _Mapping]] = ...) -> None: ...

class Report(_message.Message):
    __slots__ = ("title", "body")
    TITLE_FIELD_NUMBER: _ClassVar[int]
    BODY_FIELD_NUMBER: _ClassVar[int]
    title: str
    body: str
    def __init__(self, title: _Optional[str] = ..., body: _Optional[str] = ...) -> None: ...
