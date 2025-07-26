import { Module } from '@nestjs/common';
import { AppsModule } from './apps/apps.module';

@Module({
  imports: [AppsModule],
  controllers: [],
  providers: [],
})
export class AppModule {}
