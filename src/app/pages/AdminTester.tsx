import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { ArrowLeft, RefreshCw, ShieldAlert, ShieldCheck } from 'lucide-react';
import { apiGet, apiPost } from '../lib/api';
import { monitoringEnabled, sendClientTestError } from '../lib/monitoring';
import { Badge } from '../components/ui/badge';
import { Button } from '../components/ui/button';
import { Card, CardContent } from '../components/ui/card';
import { usePageMeta } from '../components/PageMeta';

export default function AdminTester() {
  usePageMeta('Admin · Live Tester','Non-destructive runtime checks for the Verse platform.');
  const [data,setData]=useState<any>();
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState('');
  async function run() { setLoading(true); setError(''); try { setData(await apiGet('/admin/tester')); } catch(e:any) { setData(undefined); setError(e.message||'Unable to run platform checks.'); } finally { setLoading(false); } }
  useEffect(()=>{void run()},[]);
  const [alertStatus,setAlertStatus]=useState('');
  const [alertBusy,setAlertBusy]=useState(false);
  async function sendClientError() {
    setAlertBusy(true);
    try { const id=await sendClientTestError(); setAlertStatus(id?`Client test error sent (event ${id.slice(0,8)}). Check the verse-web project in Sentry.`:'Client error tracking is not active in this build.'); }
    finally { setAlertBusy(false); }
  }
  async function sendServerError() {
    setAlertBusy(true);
    try { const result=await apiPost<{captured:boolean;eventId?:string}>('/admin/health/sentry-test'); setAlertStatus(result.captured?`Server test error sent (event ${String(result.eventId||'').slice(0,8)}). Check the verse-api project in Sentry.`:'Server error tracking is off: SENTRY_DSN is not set on the API.'); }
    catch(e:any) { setAlertStatus(e.message||'Could not reach the API.'); }
    finally { setAlertBusy(false); }
  }
  const alerting=<Card className="bg-white/[.045] border-white/10 mt-7"><CardContent className="p-5"><h2 className="text-lg font-semibold">Error alerting</h2><p className="text-sm text-slate-400 mt-1">{monitoringEnabled()?'Client error tracking is configured for this build.':'Client error tracking is off (VITE_SENTRY_DSN not set for this build).'} Test errors are tagged verse_test and safe to resolve.</p><div className="flex flex-wrap gap-3 mt-4">{monitoringEnabled()&&<Button variant="outline" disabled={alertBusy} onClick={()=>void sendClientError()}>Send test error</Button>}<Button variant="outline" disabled={alertBusy} onClick={()=>void sendServerError()}>Send server test error</Button></div>{alertStatus&&<p className="text-sm text-slate-300 mt-3" role="status">{alertStatus}</p>}</CardContent></Card>;
  return <div className="min-h-screen bg-slate-950 text-white"><main className="max-w-5xl mx-auto px-5 py-10"><Link to="/admin" className="text-sm text-slate-400"><ArrowLeft aria-hidden="true" size={14} className="inline mr-1"/>Back to admin</Link><div className="flex flex-col sm:flex-row justify-between gap-4 mt-5"><div><h1 className="text-4xl font-bold">Verse Live Tester</h1><p className="text-slate-400 mt-2">Non-destructive runtime checks for database integrity, configuration and critical platform dependencies.</p></div><Button onClick={()=>void run()} disabled={loading}><RefreshCw size={16} className={`mr-2 ${loading?'animate-spin':''}`}/>{loading?'Running…':'Run checks'}</Button></div>{error&&<div className="mt-7 rounded-xl border border-rose-400/20 bg-rose-500/10 p-5 text-center" role="alert"><p className="text-rose-200">{error}</p><Button variant="outline" className="mt-4" onClick={()=>void run()}>Try again</Button></div>}{alerting}{data?.summary&&<><Card className="bg-white/[.055] border-white/10 mt-7"><CardContent className="p-6 flex items-center gap-4">{data.summary.healthy?<ShieldCheck className="text-emerald-300" size={30}/>:<ShieldAlert className="text-rose-300" size={30}/>}<div><div className="text-2xl font-bold">{data.summary.passed}/{data.summary.total} checks passed</div><div className="text-sm text-slate-500">Generated {new Date(data.generatedAt).toLocaleString()}</div></div></CardContent></Card><div className="space-y-3 mt-5">{(data.checks||[]).map((check:any)=><Card key={check.name} className="bg-white/[.045] border-white/10"><CardContent className="p-4 flex justify-between gap-4"><div><div className="font-medium">{check.name}</div><div className="text-xs text-slate-500 mt-1 break-all">{check.detail}</div></div><Badge className={check.pass?'bg-emerald-500/15 text-emerald-300':'bg-rose-500/15 text-rose-300'}>{check.pass?'PASS':'FAIL'}</Badge></CardContent></Card>)}</div></>}</main></div>;
}
