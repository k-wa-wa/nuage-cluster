import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { SwaggerModule, DocumentBuilder } from '@nestjs/swagger';
import * as path from 'path';
import { writeFileSync } from 'fs';
import { dump } from 'js-yaml';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  const config = new DocumentBuilder()
    .setTitle('BFF API')
    .setDescription('The BFF API description')
    .setVersion('1.0')
    .build();
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api', app, document);

  const outputPath = path.resolve(process.cwd(), 'openapi.yaml');
  writeFileSync(outputPath, dump(document, {}));

  await app.listen(3000);
}
bootstrap();
