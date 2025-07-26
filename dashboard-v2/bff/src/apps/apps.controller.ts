import { Controller, Get } from '@nestjs/common';
import { AppsService } from './apps.service';
import { ApiProperty, ApiResponse } from '@nestjs/swagger';

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
  constructor(private readonly appsService: AppsService) {}

  @Get()
  @ApiResponse({
    status: 200,
    type: [App],
  })
  getApps(): App[] {
    // In a real scenario, this would proxy to another API
    // For now, return dummy data
    return [];
  }
}
