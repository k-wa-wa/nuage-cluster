import { Controller, Get } from '@nestjs/common';
import { AppsService } from './apps.service';

interface Transition {
  name: string;
  url: string;
}

interface App {
  name: string;
  description: string;
  transitions: Transition[];
}

@Controller('api/apps')
export class AppsController {
  constructor(private readonly appsService: AppsService) {}

  @Get()
  getApps(): App[] {
    // In a real scenario, this would proxy to another API
    // For now, return dummy data
    return [
      {
        name: 'App 1',
        description: 'Description for App 1',
        transitions: [
          { name: 'View App 1', url: '/app1' },
          { name: 'Settings App 1', url: '/app1/settings' },
        ],
      },
      {
        name: 'App 2',
        description: 'Description for App 2',
        transitions: [
          { name: 'View App 2', url: '/app2' },
        ],
      },
    ];
  }
}
