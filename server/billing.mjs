import crypto from 'node:crypto';

export const BILLING_PLANS = {
  free: {code:'free', name:'Starter', monthly:0, trialDays:0, activePosts:1, seats:1, shortlist:20, bookings:3},
  pro: {code:'pro', name:'Pro', monthly:249900, trialDays:14, activePosts:10, seats:3, shortlist:250, bookings:50},
  studio: {code:'studio', name:'Studio', monthly:599900, trialDays:14, activePosts:40, seats:10, shortlist:1500, bookings:250},
  enterprise: {code:'enterprise', name:'Enterprise', monthly:null, trialDays:30, activePosts:9999, seats:9999, shortlist:99999, bookings:99999}
};

export function planFor(code){ return BILLING_PLANS[code] || BILLING_PLANS.free; }
export function razorpayConfigured(){ return !!(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET); }
export async function createGatewaySubscription({planCode,customerEmail,customerName,trialDays}){
  const plan=planFor(planCode);
  if(plan.monthly===null) throw new Error('Enterprise subscriptions require sales-assisted activation.');
  if(plan.monthly===0) return {provider:'internal',providerSubscriptionId:null,checkout:null,status:'active'};
  if(!razorpayConfigured()) return {provider:'mock',providerSubscriptionId:`mock_${crypto.randomUUID()}`,checkout:{mode:'mock',message:'Configure Razorpay keys and plan IDs for live checkout.'},status:'trialing'};
  const providerPlanId=process.env[`RAZORPAY_PLAN_${planCode.toUpperCase()}`];
  if(!providerPlanId) throw new Error(`Missing Razorpay plan id for ${planCode}.`);
  const startAt=Math.floor((Date.now()+(trialDays||0)*864e5)/1000);
  const auth=Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const response=await fetch('https://api.razorpay.com/v1/subscriptions',{method:'POST',headers:{Authorization:`Basic ${auth}`,'Content-Type':'application/json'},body:JSON.stringify({plan_id:providerPlanId,total_count:120,quantity:1,customer_notify:true,start_at:startAt,notes:{planCode,customerEmail,customerName}})});
  const data=await response.json();
  if(!response.ok) throw new Error(data?.error?.description || 'Unable to create Razorpay subscription.');
  return {provider:'razorpay',providerSubscriptionId:data.id,checkout:{mode:'razorpay',keyId:process.env.RAZORPAY_KEY_ID,subscriptionId:data.id},status:'pending'};
}
export function verifyRazorpayWebhook(rawBody,signature){
  const secret=process.env.RAZORPAY_WEBHOOK_SECRET;
  if(!secret||!signature)return false;
  const digest=crypto.createHmac('sha256',secret).update(rawBody).digest('hex');
  try{return crypto.timingSafeEqual(Buffer.from(digest),Buffer.from(signature));}catch{return false;}
}

export async function createGatewayOrder({amount,currency='INR',receipt,notes={}}){
  if(!Number.isInteger(amount)||amount<=0)throw new Error('Invalid payment amount.');
  if(!razorpayConfigured())return {provider:'mock',providerOrderId:`mock_order_${crypto.randomUUID()}`,checkout:{mode:'mock',amount,currency,message:'Configure Razorpay keys for live booking payments.'}};
  const auth=Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const response=await fetch('https://api.razorpay.com/v1/orders',{method:'POST',headers:{Authorization:`Basic ${auth}`,'Content-Type':'application/json'},body:JSON.stringify({amount,currency,receipt:String(receipt).slice(0,40),notes})});
  const data=await response.json();if(!response.ok)throw new Error(data?.error?.description||'Unable to create Razorpay order.');
  return {provider:'razorpay',providerOrderId:data.id,checkout:{mode:'razorpay',keyId:process.env.RAZORPAY_KEY_ID,orderId:data.id,amount:data.amount,currency:data.currency}};
}
export function verifyRazorpayPaymentSignature({orderId,paymentId,signature}){
  if(!process.env.RAZORPAY_KEY_SECRET||!orderId||!paymentId||!signature)return false;
  const digest=crypto.createHmac('sha256',process.env.RAZORPAY_KEY_SECRET).update(`${orderId}|${paymentId}`).digest('hex');
  try{return crypto.timingSafeEqual(Buffer.from(digest),Buffer.from(signature));}catch{return false;}
}

export async function cancelGatewaySubscription(providerSubscriptionId,{atCycleEnd=true}={}){
  if(!providerSubscriptionId)throw new Error('Missing provider subscription id.');
  if(!razorpayConfigured()||String(providerSubscriptionId).startsWith('mock_'))return {provider:'mock',status:atCycleEnd?'scheduled':'cancelled'};
  const auth=Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString('base64');
  const response=await fetch(`https://api.razorpay.com/v1/subscriptions/${encodeURIComponent(providerSubscriptionId)}/cancel`,{method:'POST',headers:{Authorization:`Basic ${auth}`,'Content-Type':'application/json'},body:JSON.stringify({cancel_at_cycle_end:!!atCycleEnd})});
  const data=await response.json();
  if(!response.ok)throw new Error(data?.error?.description||'Unable to cancel Razorpay subscription.');
  return {provider:'razorpay',status:data.status||'cancelled',data};
}
