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
    res.json([
      {
        name: 'Proxmox',
        description: '',
        groupName: 'Operation',
        appLinks: [{ name: 'Visit', url: 'https://192.168.5.21:8006/' }],
      },
      {
        name: 'Grafana',
        description: '',
        groupName: 'Operation',
        appLinks: [
          { name: 'Dashboards', url: 'https://grafana.dev.nuage/dashboards' },
        ],
      },
      {
        name: 'Argo Workflow',
        description: '',
        groupName: 'Operation',
        appLinks: [
          { name: 'workflows', url: 'https://workflow.dev.nuage/workflows/' },
        ],
      },
      {
        name: 'File server',
        description: '',
        groupName: 'Pechka',
        appLinks: [{ name: 'Visit', url: 'https://file-server.nuage' }],
      },
    ]);

    //try {
    //  return await this.proxyService.proxyToAppsApi(req, res, next);
    //} catch (e) {
    //  console.log(e);
    //}
  }
}
