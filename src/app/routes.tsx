import {createBrowserRouter} from 'react-router';import React from 'react';import {ProtectedRoute} from './components/ProtectedRoute';import {PageLoading} from './components/ExperienceStates';
const L=(f:()=>Promise<any>)=>React.lazy(f);
const LandingPage=L(()=>import('./pages/LandingPage'));
const AuthPage=L(()=>import('./pages/AuthPage'));
const JobSeekerDashboard=L(()=>import('./pages/JobSeekerDashboard'));
const EmployerDashboard=L(()=>import('./pages/EmployerDashboard'));
const JobSearch=L(()=>import('./pages/JobSearch'));
const SavedJobs=L(()=>import('./pages/SavedJobs'));
const JobDetails=L(()=>import('./pages/JobDetails'));
const ProfileSetup=L(()=>import('./pages/ProfileSetup'));
const CompanyProfile=L(()=>import('./pages/CompanyProfile'));
const Portfolio=L(()=>import('./pages/Portfolio'));
const ApplicationTracking=L(()=>import('./pages/ApplicationTracking'));
const EmployerApplications=L(()=>import('./pages/EmployerApplications'));
const PostJob=L(()=>import('./pages/PostJob'));
const CandidateSearch=L(()=>import('./pages/CandidateSearch'));
const Messages=L(()=>import('./pages/Messages'));
const CareerResources=L(()=>import('./pages/CareerResources'));
const Reviews=L(()=>import('./pages/Reviews'));
const Pricing=L(()=>import('./pages/Pricing'));
const Notifications=L(()=>import('./pages/Notifications'));
const NotFound=L(()=>import('./pages/NotFound'));
const AdminDashboard=L(()=>import('./pages/AdminDashboard'));
const Guide=L(()=>import('./pages/Guide'));
const JobAlerts=L(()=>import('./pages/JobAlerts'));
const CandidateCompare=L(()=>import('./pages/CandidateCompare'));
const BuildMyCrew=L(()=>import('./pages/BuildMyCrew'));
const AdminTester=L(()=>import('./pages/AdminTester'));
const IntentHub=L(()=>import('./pages/IntentHub'));
const GlobalSearch=L(()=>import('./pages/GlobalSearch'));
const SiteMapPage=L(()=>import('./pages/public/SiteMapPage'));
const PublicJobs=L(()=>import('./pages/public/PublicJobs'));
const PublicOpportunity=L(()=>import('./pages/public/PublicOpportunity'));
const PublicTalent=L(()=>import('./pages/public/PublicTalent'));
const PublicProfile=L(()=>import('./pages/public/PublicProfile'));
const PublicActs=L(()=>import('./pages/public/PublicActs'));
const PublicAct=L(()=>import('./pages/public/PublicAct'));
const LegalPage=L(()=>import('./pages/public/LegalPage'));
const UrgentRequests=L(()=>import('./pages/UrgentRequests'));
const Availability=L(()=>import('./pages/Availability'));
const VerifyEmail=L(()=>import('./pages/VerifyEmail'));
const ForgotPassword=L(()=>import('./pages/ForgotPassword'));
const ResetPassword=L(()=>import('./pages/ResetPassword'));
const Workspace=L(()=>import('./pages/Workspace'));
const ActsManager=L(()=>import('./pages/ActsManager'));
const BookTalent=L(()=>import('./pages/BookTalent'));
const Bookings=L(()=>import('./pages/Bookings'));
const BandBuilder=L(()=>import('./pages/BandBuilder'));
const Billing=L(()=>import('./pages/Billing'));
const S=({children}:{children:React.ReactNode})=><React.Suspense fallback={<PageLoading/>}>{children}</React.Suspense>;
const P=({roles,children}:{roles:any[];children:React.ReactNode})=><S><ProtectedRoute roles={roles}>{children}</ProtectedRoute></S>;
export const router=createBrowserRouter([{path:'/',element:<S><LandingPage/></S>},
{path:'/pricing',element:<S><Pricing/></S>},
{path:'/start',element:<S><IntentHub/></S>},
{path:'/guide',element:<S><Guide/></S>},
{path:'/search',element:<S><GlobalSearch/></S>},
{path:'/sitemap',element:<S><SiteMapPage/></S>},
{path:'/music-jobs',element:<S><PublicJobs/></S>},
{path:'/opportunities/:id',element:<S><PublicOpportunity/></S>},
{path:'/music-professionals',element:<S><PublicTalent/></S>},
{path:'/professionals/:id',element:<S><PublicProfile/></S>},
{path:'/book-music',element:<S><PublicActs/></S>},
{path:'/acts/:id',element:<S><PublicAct/></S>},
{path:'/about',element:<S><LegalPage/></S>},
{path:'/terms',element:<S><LegalPage/></S>},
{path:'/privacy',element:<S><LegalPage/></S>},
{path:'/safety',element:<S><LegalPage/></S>},
{path:'/cookies',element:<S><LegalPage/></S>},
{path:'/refund-policy',element:<S><LegalPage/></S>},
{path:'/community-guidelines',element:<S><LegalPage/></S>},
{path:'/accessibility',element:<S><LegalPage/></S>},
{path:'/contact',element:<S><LegalPage/></S>},
{path:'/verify-email',element:<S><VerifyEmail/></S>},
{path:'/forgot-password',element:<S><ForgotPassword/></S>},
{path:'/reset-password',element:<S><ResetPassword/></S>},
{path:'/auth/:userType',element:<S><AuthPage/></S>},
{path:'/jobseeker',children:[{index:true,element:<P roles={['jobseeker']}><JobSeekerDashboard/></P>},
{path:'profile',element:<P roles={['jobseeker']}><ProfileSetup/></P>},
{path:'portfolio',element:<P roles={['jobseeker']}><Portfolio/></P>},
{path:'applications',element:<P roles={['jobseeker']}><ApplicationTracking/></P>},
{path:'jobs',element:<P roles={['jobseeker']}><JobSearch/></P>},
{path:'saved',element:<P roles={['jobseeker']}><SavedJobs/></P>},
{path:'alerts',element:<P roles={['jobseeker']}><JobAlerts/></P>},
{path:'jobs/:id',element:<P roles={['jobseeker']}><JobDetails/></P>},
{path:'messages',element:<P roles={['jobseeker']}><Messages/></P>},
{path:'notifications',element:<P roles={['jobseeker']}><Notifications/></P>},
{path:'resources',element:<P roles={['jobseeker']}><CareerResources/></P>},
{path:'reviews',element:<P roles={['jobseeker']}><Reviews/></P>},
{path:'acts',element:<P roles={['jobseeker']}><ActsManager/></P>},
{path:'book-talent',element:<P roles={['jobseeker']}><BookTalent/></P>},
{path:'bookings',element:<P roles={['jobseeker']}><Bookings/></P>},
{path:'band-builder',element:<P roles={['jobseeker']}><BandBuilder/></P>},
{path:'urgent',element:<P roles={['jobseeker']}><UrgentRequests/></P>},
{path:'availability',element:<P roles={['jobseeker']}><Availability/></P>},
{path:'hiring/post',element:<P roles={['jobseeker']}><PostJob/></P>},
{path:'hiring/talent',element:<P roles={['jobseeker']}><CandidateSearch/></P>},
{path:'compare',element:<P roles={['jobseeker']}><CandidateCompare/></P>},
{path:'build-my-crew',element:<P roles={['jobseeker']}><BuildMyCrew/></P>},
{path:'hiring/applicants',element:<P roles={['jobseeker']}><EmployerApplications/></P>},
{path:'billing',element:<P roles={['jobseeker']}><Billing/></P>},
{path:'workspace',element:<P roles={['jobseeker']}><Workspace/></P>}]},
{path:'/employer',children:[{index:true,element:<P roles={['employer']}><EmployerDashboard/></P>},
{path:'profile',element:<P roles={['employer']}><CompanyProfile/></P>},
{path:'post-job',element:<P roles={['employer']}><PostJob/></P>},
{path:'candidates',element:<P roles={['employer']}><CandidateSearch/></P>},
{path:'compare',element:<P roles={['employer']}><CandidateCompare/></P>},
{path:'build-my-crew',element:<P roles={['employer']}><BuildMyCrew/></P>},
{path:'applications',element:<P roles={['employer']}><EmployerApplications/></P>},
{path:'jobs/:id',element:<P roles={['employer']}><JobDetails/></P>},
{path:'messages',element:<P roles={['employer']}><Messages/></P>},
{path:'notifications',element:<P roles={['employer']}><Notifications/></P>},
{path:'acts',element:<P roles={['employer']}><ActsManager/></P>},
{path:'book-talent',element:<P roles={['employer']}><BookTalent/></P>},
{path:'bookings',element:<P roles={['employer']}><Bookings/></P>},
{path:'band-builder',element:<P roles={['employer']}><BandBuilder/></P>},
{path:'urgent',element:<P roles={['employer']}><UrgentRequests/></P>},
{path:'availability',element:<P roles={['employer']}><Availability/></P>},
{path:'billing',element:<P roles={['employer']}><Billing/></P>},
{path:'workspace',element:<P roles={['employer']}><Workspace/></P>}]},
{path:'/admin',element:<P roles={['admin']}><AdminDashboard/></P>},
{path:'/admin/tester',element:<P roles={['admin']}><AdminTester/></P>},
{path:'*',element:<S><NotFound/></S>}]);
