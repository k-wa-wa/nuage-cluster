import { Module } from '@nestjs/common';
import { AppsController } from './apps.controller';
import { AppsService } from './apps.service';
import { ProxyService } from 'libs/proxy';

@Module({
  controllers: [AppsController],
  providers: [AppsService, ProxyService],
})
export class AppsModule {}
