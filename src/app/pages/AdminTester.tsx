import { useEffect, useState } from 'react';
import { Link } from 'react-router';
import { ArrowLeft, RefreshCw, ShieldAlert, ShieldCheck } from 'lucide-react';
import { apiGet } from '../lib/api';
import { Badge } from '../components/ui/badge';
import { Button } from '../components/ui/button';
import { Card, CardContent } from '../components/ui/card';

export default function AdminTester() {
  const [data,setData]=useState<any>();
  const [loading,setLoading]=useState(false);
  const [error,setError]=useState('');
  async function run() { setLoading(true); setError(''); try { setData(await apiGet('/admin/tester')); } catch(e:any) { setData(undefined); setError(e.message||'Unable to run platform checks.'); } finally { setLoading(false); } }
  useEffect(()=>{void run()},[]);
  return <div className="min-h-screen bg-slate-950 text-white"><main className="max-w-5xl mx-auto px-5 py-10"><Link to="/admin" className="text-sm text-slate-400"><ArrowLeft size={14} className="inline mr-1"/>Admin</Link><div className="flex justify-between gap-4 mt-5"><div><h1 className="text-4xl font-bold">Verse Live Tester</h1><p className="text-slate-400 mt-2">Non-destructive runtime checks for database integrity, configuration and critical platform dependencies.</p></div><Button onClick={()=>void run()} disabled={loading}><RefreshCw size={16} className={`mr-2 ${loading?'animate-spin':''}`}/>{loading?'Running…':'Run checks'}</Button></div>{error&&<div className="mt-7 rounded-xl border border-rose-400/20 bg-rose-500/10 p-5 text-center" role="alert"><p className="text-rose-200">{error}</p><Button variant="outline" className="mt-4" onClick={()=>void run()}>Try again</Button></div>}{data&&<><Card className="bg-white/[.055] border-white/10 mt-7"><CardContent className="p-6 flex items-center gap-4">{data.summary.healthy?<ShieldCheck className="text-emerald-300" size={30}/>:<ShieldAlert className="text-rose-300" size={30}/>}<div><div className="text-2xl font-bold">{data.summary.passed}/{data.summary.total} checks passed</div><div className="text-sm text-slate-500">Generated {new Date(data.generatedAt).toLocaleString()}</div></div></CardContent></Card><div className="space-y-3 mt-5">{data.checks.map((check:any)=><Card key={check.name} className="bg-white/[.045] border-white/10"><CardContent className="p-4 flex justify-between gap-4"><div><div className="font-medium">{check.name}</div><div className="text-xs text-slate-500 mt-1 break-all">{check.detail}</div></div><Badge className={check.pass?'bg-emerald-500/15 text-emerald-300':'bg-rose-500/15 text-rose-300'}>{check.pass?'PASS':'FAIL'}</Badge></CardContent></Card>)}</div></>}</main></div>;
}
