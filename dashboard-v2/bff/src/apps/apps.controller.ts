import { Controller, Get, Next, Req, Res } from '@nestjs/common';
import { AppsService } from './apps.service';
import { ApiProperty, ApiResponse } from '@nestjs/swagger';
import { ProxyService } from 'libs/proxy';

class Transition {
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

  @ApiProperty({ type: [Transition] })
  transitions: Transition[];
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
  async getApps(@Req() req, @Res() res, @Next() next) {
    try {
      return await this.proxyService.proxyToAppsApi(req, res, next);
    } catch (e) {
      console.log(e);
    }
  }
}
