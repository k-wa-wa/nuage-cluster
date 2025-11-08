from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class GenerateReportRequest(_message.Message):
    __slots__ = ("user_id", "instructions", "context")
    USER_ID_FIELD_NUMBER: _ClassVar[int]
    INSTRUCTIONS_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_FIELD_NUMBER: _ClassVar[int]
    user_id: str
    instructions: str
    context: str
    def __init__(self, user_id: _Optional[str] = ..., instructions: _Optional[str] = ..., context: _Optional[str] = ...) -> None: ...

class GenerateReportResponse(_message.Message):
    __slots__ = ("success", "message", "report")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    REPORT_FIELD_NUMBER: _ClassVar[int]
    success: bool
    message: str
    report: Report
    def __init__(self, success: bool = ..., message: _Optional[str] = ..., report: _Optional[_Union[Report, _Mapping]] = ...) -> None: ...

class Report(_message.Message):
    __slots__ = ("title", "body")
    TITLE_FIELD_NUMBER: _ClassVar[int]
    BODY_FIELD_NUMBER: _ClassVar[int]
    title: str
    body: str
    def __init__(self, title: _Optional[str] = ..., body: _Optional[str] = ...) -> None: ...
