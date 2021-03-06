program seis2d_wave_injec

!----------------------------------------------------------------------------
! This is the main program to simulate 2D P-SV seismic wave propagation.
!
! Author: 
!       Wenzhong CAO    Email: caowz@mail.ustc.edu.cn
!       Wei ZHANG       Email: zhangwei.zw@gmail.com
! Copyright (C) 2017 Wenzhong CAO & Wei ZHANG
!----------------------------------------------------------------------------

!{ -- declare module used --
use para_mod
use io_mod
use nompi_mod
use media_mod
use src_mod
use abs_exp_mod
use abs_cfs_mod
use abs_dpcfs_mod
use solver_mod
use grid_mod
!use injec_mod
!} -- end declare module used ---

implicit none
integer :: ntime,loc_ntime,ierr
logical :: is_rest
integer,parameter ::      &
  ABS_EXP         =1,     &
  ABS_CFS         =2,     &
  ABS_DPOLECFS    =3

call get_conf_name(fnm_conf)
call para_basic_init(fnm_conf)

call swmpi_init(fnm_conf)
call cart_creat

call para_init(fnm_conf)
call swmpi_reinit_para

call grid_fnm_init(fnm_conf)
call grid_coord_alloc
call grid_coord_import

call media_fnm_init(fnm_conf)
call media_alloc
call media_import

call src_fnm_init(fnm_conf)
call src_import

!-- read injection source info.
!call injec_src_read(fnm_src_conf)

call io_init(fnm_conf)
call io_snap_read(fnm_conf)
call io_snap_locate(thisid(1),thisid(2))
call io_pt_import
call io_seismo_init

call solver_init

if(abs_type==ABS_EXP) then
  call abs_exp_init(fnm_conf)
elseif (abs_type==ABS_CFS) then
  call abs_cfs_init(fnm_conf)
elseif (abs_type==ABS_DPOLECFS) then
  call abs_dpcfs_init(fnm_conf)
else 
  print *, "There are no abs_type "
  stop 1
end if

ntime=0

call io_rest_import(P,Vx,Vz,ntime)
if (ntime>0) then
  if(abs_type==ABS_EXP) then
    call abs_exp_rest_import(pnm_rest)
  elseif(abs_type==ABS_CFS) then
    call abs_cfs_rest_import(pnm_rest)
  elseif(abs_type==ABS_DPOLECFS) then
    call abs_dpcfs_rest_import(pnm_rest)
  end if
end if

call swmpi_time_init(fnm_log,ntime)

#ifdef FourthORDER
  print *, "This is 4th-order source injection code"
#else
  if (CondFreeAFDA .eqv. .true.) then
    print *, "CondFreeAFDA should be set to false."
    stop 1
  end if
  print *, "This is 2nd-order source injection code"
#endif

!#############################################################################
!## main time loop
!#############################################################################
loop_time: do

  if ( ntime>nt ) exit

!  if ( InjecSrc==1 ) then
!    if ( mod(ntime,injec_per_import)==0 ) then
!      call injec_src_import(ntime,nt)
!      loc_ntime=1
!    end if
!  end if

  call swmpi_time_write(ntime,fnm_log)

  !==== set current time to the time level of velocity components ====
  call set_cur_time(ntime,0.0)

  !==== hook law equation to update stresses ====
  call update_hook

  !==== absorbing before adding source for plane wave ====
  if (abs_type==ABS_EXP) then
    call abs_exp_hook
  elseif (abs_type==ABS_CFS) then
    call abs_cfs_hook
  elseif (abs_type==ABS_DPOLECFS) then
    call abs_dpcfs_hook
  end if

  !==== moment source ====
  call src_stress(P,ntime,stept)

#ifdef WITHQS
  !==== approximated attenuation effect ====
  call atten_T 
#endif

  !==== injec src hook 
!  if ( InjecSrc==1 ) then
!    call injec_src_hook(Txx,Tzz,Txz,loc_ntime,stept)
!  end if

  !==== set current time to the time level of stress components ====
  call set_cur_time(ntime,0.5)

  !==== momentum equation to update velocites ====
  call update_momentum

  !==== absorbing before adding source for plane wave ====
  if (abs_type==ABS_EXP) then
    call abs_exp_momentum
  elseif (abs_type==ABS_CFS) then
    call abs_cfs_momentum
  elseif (abs_type==ABS_DPOLECFS) then
    call abs_dpcfs_momentum
  end if

  !==== force source ====
  call src_force(Vx,Vz,ntime,stept)
  call src_resrc(Vx,Vz,ntime,stept)

#ifdef WITHQS
  !==== approximated attenuation effect ====
  call atten_V
#endif

  !==== injec src momentum
!  if ( InjecSrc==1 ) then
!    call injec_src_momentum(Vx,Vz,loc_ntime,stept)
!  end if

  !==== save result ====
  ntime=ntime+1
  loc_ntime=loc_ntime+1
  call io_seismo_put(Vx,Vz,P,ntime)
  call io_wave_export(Vx,Vz,ntime,stept)
#ifndef LITE
  call io_stress_export(P,ntime,stept)
#endif

  !==== check largest value and output checkpoint files ====
  call solver_check(ntime)
  call io_rest_export(P,Vx,Vz,ntime,is_rest)
  if (is_rest) then
    if (abs_type==ABS_EXP) then
      call abs_exp_rest_export(pnm_rest)
    elseif (abs_type==ABS_CFS) then
      call abs_cfs_rest_export(pnm_rest)
    elseif (abs_type==ABS_DPOLECFS) then
      call abs_dpcfs_rest_export(pnm_rest)
    end if
  end if

end do loop_time
!#############################################################################

call io_seismo_close
call io_wave_close
#ifndef LITE
call io_stress_close
#endif
call swmpi_time_end(fnm_log)

call solver_destroy
call grid_destroy
call media_destroy
call src_destroy

!-----------------------------------------------------------------------!
!contains
!-----------------------------------------------------------------------!

end program seis2d_wave_injec

! vim:ft=fortran:ts=2:sw=2:nu:et:ai:
