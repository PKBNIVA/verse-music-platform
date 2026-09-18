import crypto from 'node:crypto';

export function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return { salt, hash: crypto.scryptSync(password, salt, 64).toString('hex') };
}
export function verifyPassword(password, salt, expected) {
  try {
    const actual = Buffer.from(crypto.scryptSync(password,salt,64).toString('hex'),'hex');
    const target = Buffer.from(expected,'hex');
    return actual.length === target.length && crypto.timingSafeEqual(actual,target);
  } catch { return false; }
}
export const tokenHash=(token)=>crypto.createHash('sha256').update(token).digest('hex');
export const newToken=()=>crypto.randomBytes(32).toString('hex');
export function parseCookies(req){
  return Object.fromEntries(String(req.headers.cookie||'').split(';').map(x=>x.trim()).filter(Boolean).map(p=>{const i=p.indexOf('=');return [decodeURIComponent(p.slice(0,i)),decodeURIComponent(p.slice(i+1))]}));
}
export function sessionCookie(token, maxAge=7*86400){
  const secure=(process.env.NODE_ENV==='production'||process.env.SESSION_COOKIE_SECURE==='true')?'; Secure':'';
  return `verse_session=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}
export function clearSessionCookie(){return `verse_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${(process.env.NODE_ENV==='production'||process.env.SESSION_COOKIE_SECURE==='true')?'; Secure':''}`;}

const buckets=new Map();
export function rateLimit(key, limit=300, windowMs=15*60_000){
  const now=Date.now(); let b=buckets.get(key);
  if(!b||b.resetAt<=now){b={count:0,resetAt:now+windowMs};buckets.set(key,b);}
  b.count++; return {ok:b.count<=limit, remaining:Math.max(0,limit-b.count), resetAt:b.resetAt};
}
export function securityHeaders(res){
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('X-Frame-Options','DENY');
  res.setHeader('Referrer-Policy','strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy','camera=(), microphone=(), geolocation=()');
  res.setHeader('Cross-Origin-Opener-Policy','same-origin');
  res.setHeader('Cross-Origin-Resource-Policy','same-site');
  res.setHeader('Content-Security-Policy',"default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; img-src 'self' data: https:; media-src 'self' https:; style-src 'self' 'unsafe-inline'; script-src 'self' https://checkout.razorpay.com; connect-src 'self' https://api.razorpay.com; frame-src https://api.razorpay.com https://checkout.razorpay.com");
  if(process.env.NODE_ENV==='production')res.setHeader('Strict-Transport-Security','max-age=31536000; includeSubDomains');
}
