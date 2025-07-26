import { createProxyMiddleware, RequestHandler } from 'http-proxy-middleware';
import { Injectable } from '@nestjs/common';

@Injectable()
export class ProxyService {
  // This service would handle the actual proxy logic to the external API
  // For now, the controller directly returns dummy data.
  // If complex logic or external API calls were needed, they would go here.
  proxyToAppsApi: RequestHandler;

  constructor() {
    //this.proxyToAppsApi = createProxyMiddleware({
    //  target: process.env.BACKEND_API_URL_FOR_APPS,
    //  changeOrigin: true,
    //  ws: true,
    //});
  }
}
