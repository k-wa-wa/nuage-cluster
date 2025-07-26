import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { AppsModule } from './apps/apps.module';

@Module({
  imports: [AppsModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
