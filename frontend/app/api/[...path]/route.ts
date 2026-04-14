const BACKEND_URL = process.env.BACKEND_URL;

export const dynamic = 'force-dynamic';

async function proxy(
  req: Request,
  { params }: { params: Promise<{ path: string[] }> }
) {
  if (!BACKEND_URL) {
    return new Response('BACKEND_URL not set', { status: 500 });
  }

  const { path } = await params;
  const url = `${BACKEND_URL}/${path.join('/')}`;

  const headers = new Headers(req.headers);
  headers.delete('host');
  headers.delete('content-length');

  const body =
    req.method === 'GET' || req.method === 'HEAD'
      ? undefined
      : await req.arrayBuffer();

  const upstream = await fetch(url, {
    method: req.method,
    headers,
    body,
  });

  const resHeaders = new Headers(upstream.headers);
  resHeaders.delete('content-encoding');
  resHeaders.delete('content-length');
  resHeaders.delete('transfer-encoding');

  return new Response(upstream.body, {
    status: upstream.status,
    headers: resHeaders,
  });
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const DELETE = proxy;
export const PATCH = proxy;
