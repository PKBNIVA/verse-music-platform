import { Navigate, useLocation } from 'react-router';
import { useAuth, Role } from '../lib/authContext';
import { hasAccessToken } from '../lib/api';
import { Button } from './ui/button';
import { PageLoading } from './ExperienceStates';
export function ProtectedRoute({roles,children}:{roles:Role[];children:React.ReactNode}){
 const {user,loading,refresh}=useAuth(); const location=useLocation();
 if(loading) return <PageLoading label="Restoring your workspace"/>;
 if(!user&&hasAccessToken()) return <div role="alert" className="grid min-h-screen place-items-center bg-slate-950 px-5 text-white"><div className="max-w-sm text-center"><h1 className="text-xl font-semibold">We couldn't reach Verse</h1><p className="mt-2 text-sm text-slate-400">Your session is still saved. Check your connection and try again.</p><div className="mt-5 flex justify-center gap-3"><Button onClick={()=>{refresh()}}>Try again</Button><Button variant="outline" onClick={()=>{window.location.assign('/')}}>Go home</Button></div></div></div>;
 if(!user){const authRole=roles.includes('employer')&&!roles.includes('jobseeker')?'employer':'jobseeker';return <Navigate to={`/auth/${authRole}`} state={{from:`${location.pathname}${location.search}`}} replace/>;}
 if(!roles.includes(user.role)){const home=user.role==='admin'?'/admin':user.role==='employer'?'/employer':'/jobseeker';return <Navigate to={home} replace/>;}
 return <>{children}</>;
}
