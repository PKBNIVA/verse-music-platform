import { Navigate, useLocation } from 'react-router';
import { useAuth, Role } from '../lib/authContext';
import { PageLoading } from './ExperienceStates';
export function ProtectedRoute({roles,children}:{roles:Role[];children:React.ReactNode}){
 const {user,loading}=useAuth(); const location=useLocation();
 if(loading) return <PageLoading label="Restoring your workspace"/>;
 if(!user){const authRole=roles.includes('employer')&&!roles.includes('jobseeker')?'employer':'jobseeker';return <Navigate to={`/auth/${authRole}`} state={{from:`${location.pathname}${location.search}`}} replace/>;}
 if(!roles.includes(user.role)){const home=user.role==='admin'?'/admin':user.role==='employer'?'/employer':'/jobseeker';return <Navigate to={home} replace/>;}
 return <>{children}</>;
}
