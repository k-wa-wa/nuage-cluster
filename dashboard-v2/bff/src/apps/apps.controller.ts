import { Controller, Get, Next, Req, Res } from '@nestjs/common';
import { AppsService } from './apps.service';
import { ApiProperty, ApiResponse } from '@nestjs/swagger';
import { ProxyService } from 'libs/proxy';
import { NextFunction, Request, Response } from 'express';

class AppLink {
  @ApiProperty()
  name: string;

  @ApiProperty()
  url: string;
}

class App {
  @ApiProperty()
  name: string;

  @ApiProperty()
  description: string;

  @ApiProperty()
  groupName: string;

  @ApiProperty({ type: [AppLink] })
  appLinks: AppLink[];
}

@Controller('api/apps')
export class AppsController {
  constructor(
    private readonly appsService: AppsService,
    private readonly proxyService: ProxyService,
  ) {}

  @Get()
  @ApiResponse({
    status: 200,
    type: [App],
  })
  async getApps(
    @Req() req: Request,
    @Res() res: Response,
    @Next() next: NextFunction,
  ) {
    try {
      return await this.proxyService.proxyToAppsApi(req, res, next);
    } catch (e) {
      console.log(e);
    }
  }
}
