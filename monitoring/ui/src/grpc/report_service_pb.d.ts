import * as jspb from 'google-protobuf'



export class Report extends jspb.Message {
  getReportId(): string;
  setReportId(value: string): Report;

  getReportName(): string;
  setReportName(value: string): Report;

  getReportType(): string;
  setReportType(value: string): Report;

  getGeneratedAt(): string;
  setGeneratedAt(value: string): Report;

  getContent(): string;
  setContent(value: string): Report;

  getStatus(): string;
  setStatus(value: string): Report;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): Report.AsObject;
  static toObject(includeInstance: boolean, msg: Report): Report.AsObject;
  static serializeBinaryToWriter(message: Report, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): Report;
  static deserializeBinaryFromReader(message: Report, reader: jspb.BinaryReader): Report;
}

export namespace Report {
  export type AsObject = {
    reportId: string;
    reportName: string;
    reportType: string;
    generatedAt: string;
    content: string;
    status: string;
  };
}

export class GetReportRequest extends jspb.Message {
  getReportId(): string;
  setReportId(value: string): GetReportRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): GetReportRequest.AsObject;
  static toObject(includeInstance: boolean, msg: GetReportRequest): GetReportRequest.AsObject;
  static serializeBinaryToWriter(message: GetReportRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): GetReportRequest;
  static deserializeBinaryFromReader(message: GetReportRequest, reader: jspb.BinaryReader): GetReportRequest;
}

export namespace GetReportRequest {
  export type AsObject = {
    reportId: string;
  };
}

export class GetReportResponse extends jspb.Message {
  getReport(): Report | undefined;
  setReport(value?: Report): GetReportResponse;
  hasReport(): boolean;
  clearReport(): GetReportResponse;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): GetReportResponse.AsObject;
  static toObject(includeInstance: boolean, msg: GetReportResponse): GetReportResponse.AsObject;
  static serializeBinaryToWriter(message: GetReportResponse, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): GetReportResponse;
  static deserializeBinaryFromReader(message: GetReportResponse, reader: jspb.BinaryReader): GetReportResponse;
}

export namespace GetReportResponse {
  export type AsObject = {
    report?: Report.AsObject;
  };
}

export class ListReportsRequest extends jspb.Message {
  getReportType(): string;
  setReportType(value: string): ListReportsRequest;

  getStartDate(): string;
  setStartDate(value: string): ListReportsRequest;

  getEndDate(): string;
  setEndDate(value: string): ListReportsRequest;

  getLimit(): number;
  setLimit(value: number): ListReportsRequest;

  getOffset(): number;
  setOffset(value: number): ListReportsRequest;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): ListReportsRequest.AsObject;
  static toObject(includeInstance: boolean, msg: ListReportsRequest): ListReportsRequest.AsObject;
  static serializeBinaryToWriter(message: ListReportsRequest, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): ListReportsRequest;
  static deserializeBinaryFromReader(message: ListReportsRequest, reader: jspb.BinaryReader): ListReportsRequest;
}

export namespace ListReportsRequest {
  export type AsObject = {
    reportType: string;
    startDate: string;
    endDate: string;
    limit: number;
    offset: number;
  };
}

export class ListReportsResponse extends jspb.Message {
  getReportsList(): Array<Report>;
  setReportsList(value: Array<Report>): ListReportsResponse;
  clearReportsList(): ListReportsResponse;
  addReports(value?: Report, index?: number): Report;

  serializeBinary(): Uint8Array;
  toObject(includeInstance?: boolean): ListReportsResponse.AsObject;
  static toObject(includeInstance: boolean, msg: ListReportsResponse): ListReportsResponse.AsObject;
  static serializeBinaryToWriter(message: ListReportsResponse, writer: jspb.BinaryWriter): void;
  static deserializeBinary(bytes: Uint8Array): ListReportsResponse;
  static deserializeBinaryFromReader(message: ListReportsResponse, reader: jspb.BinaryReader): ListReportsResponse;
}

export namespace ListReportsResponse {
  export type AsObject = {
    reportsList: Array<Report.AsObject>;
  };
}

