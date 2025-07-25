      module roms_join
      
      ! ROMS functionality to facilitate partioning and joining of files

      use netcdf
      use mpi
      use nc_read_write

      private
       
      ! mpi variables
      integer,public :: part_comm,mynode,nnodes  ! mpi vars

      ! range of partial files for this node
      integer :: part0,part1,myparts,part

      ! global dimensions
      integer :: gnx,gny,nz,nzw

      ! Files
      integer,public :: nfiles ! number of src files
      integer,public :: nparts ! number of partial files
      character(len=128),public :: grdfile,srcfile,joinfile,partfile
      character(len=128),public,allocatable, dimension(:) :: srcfiles
      character(len=128),public,allocatable, dimension(:) :: partfiles

      ! Only used by mynode=0
      integer,dimension(:,:),allocatable :: iloc,jloc
      integer,dimension(:,:),allocatable :: ilcu,jlcv
      integer,dimension(:,:),allocatable :: node_map
      integer,dimension(:)  ,allocatable :: npi_c,npj_c

      ! Dimension names for in netcdf files
      character(len=7),public,parameter :: dn_xr = 'xi_rho'
      character(len=7),public,parameter :: dn_yr = 'eta_rho'
      character(len=7),public,parameter :: dn_xu = 'xi_u'
      character(len=7),public,parameter :: dn_yv = 'eta_v'
      character(len=7),public,parameter :: dn_zr = 's_rho'
      character(len=7),public,parameter :: dn_zw = 's_w'
      character(len=7),public,parameter :: dn_tm = 'time'

      
      type,public :: ncstructure
        integer                                     :: nrecords  ! number of records
        integer                                     :: nvars     ! number of variables
        integer,dimension(3)                        :: gsize     ! dimension size of the global grid (rho)
        character(len=30),dimension(:),allocatable  :: varname   ! name, if u/v or rho
        character(len=1),dimension(:), allocatable  :: vartype   ! 'f/r/u f/r/v f/r/w f/t'
        logical,dimension(:),allocatable            :: varpart   ! partitionable or not
        integer,dimension(:),allocatable            :: xtype     ! variable type
        integer,dimension(:),allocatable            :: ndims  
        integer,dimension(:),allocatable            :: natts
        type(dimstruct),dimension(:),allocatable    :: dims
        type(attstruct),dimension(:),allocatable    :: atts
      end type ncstructure

      type,public :: dimstruct
        character(len=7),dimension(:),allocatable ::dimnames
        integer,         dimension(:),allocatable ::dimsizes
      end type dimstruct

      type,public :: attstruct
        character(len=20),dimension(:),allocatable ::attnames
        character(len=200),dimension(:),allocatable ::attvalues
      end type attstruct
      
      public :: cmd_args_partit
      public :: cmd_args_ncjoin
      public :: partition_mask
      public :: make_partial_files
      public :: write_partial_files
      public :: make_joined_file
      public :: write_joined_file

      contains
! ----------------------------------------------------------------------
      subroutine cmd_args_join  ![
      implicit none

      integer :: nargs,i
      character(len=128) :: arg

      nargs =  command_argument_count()

      if (nargs < 1) call show_use_ncjoin
      
      nparts = nargs
      allocate(partfiles(0:nparts-1))
      do i = 1,nargs
        call get_command_argument(i,arg)
        read(arg,*) partfiles(i-1)
      enddo
      print *,partfiles(1)

      myparts = ceiling(nparts*1.0/nnodes)
      part0 = myparts*mynode
      part1 = min(myparts*(mynode+1) -1,nparts-1)

      end subroutine cmd_args_join !]
! ----------------------------------------------------------------------
      subroutine show_use_ncjoin  ![
      implicit none

      print *, 'Usage of ncjoin should be: ',
     &       'ncjoin file1.??.nc ...'
     
      stop

      end subroutine show_use_ncjoin !]
! ----------------------------------------------------------------------
      subroutine make_joined_file ![
      ! single node only
      implicit none

      ! local
      character(len=128) :: partfile
      character(len=128) :: att_name
      integer :: iatt,ngatt,part
      integer :: i,j,varid
      integer :: dimids(4),ndims
      integer :: ivar,nvars,xtype
      character(len=20) :: vname
      type(ncstructure)  :: ncinfo
      character(len=7),dimension(5)  ::dname
      integer         ,dimension(5)  ::dsize
      character(len=20),dimension(5) ::attname
      character(len=200),dimension(5)::attvalue
      integer :: ierr, ncid,npid
      integer :: natts,idm,vid
      integer :: idx1
      integer,dimension(2)  ::gdims
      real,dimension(:,:,:),allocatable :: var3d
      integer,dimension(4) :: startr
      integer :: record

      partfile = trim(partfiles(part0))
      idx1 = index(partfile,'.nc',back=.true.)
      joinfile = partfile(1:idx1-1)
      idx1 = index(joinfile,'.',back=.true.)
      joinfile = joinfile(1:idx1-1) //'.nc'
      print *, trim(partfile),' ',trim(joinfile)

      ! open first partial file in range 
      ierr = nf90_open(trim(partfile), nf90_nowrite, npid)
      if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'opening file: ',trim(partfile) )

      call get_nc_info(npid, ncinfo) 

      ierr = nf90_get_att(npid,nf90_global,'globaldims',gdims)
      if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'get global dims: ',trim(partfile) )
      gnx = gdims(1)
      gny = gdims(1)

      if (mynode==0) then ! single node to create joined file

        print *,'Creating joined file'

        ierr=nf90_create(trim(joinfile),nf90_netcdf4,ncid)
!       ierr=nf90_create(trim(joinfile),nf90_classic_model,ncid)
        if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'creating file: ',trim(joinfile) )

        ! read all global attributes from the partial file and write them
        ierr = nf90_inquire(npid, nAttributes=ngatt)
        if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'getting atts: ',trim(partfile) )
        do iatt = 1,ngatt
          ierr = nf90_inq_attname(npid,nf90_global,iatt,att_name)
          if (index(att_name,'globaldims')>0) cycle
          if (index(att_name,'subdompos')>0) cycle
          if (index(att_name,'partition')>0) cycle
          if (index(att_name,'start_idx')>0) cycle
          if (index(att_name,'neighbors')>0) cycle
          ierr = nf90_copy_att(npid,nf90_global,att_name,ncid,nf90_global)
        enddo 

        do ivar = 1,ncinfo%nvars
          vname   = ncinfo%varname(ivar)
          xtype   = ncinfo%xtype(ivar)
          ndims   = ncinfo%ndims(ivar)
          dsize(1:ndims) = ncinfo%dims(ivar)%dimsizes
          dname(1:ndims) = ncinfo%dims(ivar)%dimnames
          natts   = ncinfo%natts(ivar)
          attname(1:natts) = ncinfo%atts(ivar)%attnames
          attvalue(1:natts)= ncinfo%atts(ivar)%attvalues

          do idm =1,ndims
            if (index(dname(idm),'xi_rho') > 0)  dsize(idm)=gnx
            if (index(dname(idm),'xi_u') > 0)    dsize(idm)=gnx-1
            if (index(dname(idm),'eta_rho') > 0) dsize(idm)=gny
            if (index(dname(idm),'eta_v') > 0)   dsize(idm)=gny-1
            if (index(dname(idm),'time') > 0)    dsize(idm)= 0 
          enddo

          vid = nccreate(ncid,vname,dname(1:ndims),dsize(1:ndims),xtype)
          ierr = nf90_var_par_access(ncid, varid, nf90_collective)
          do iatt=1,natts
            ierr = nf90_put_att(ncid,vid,attname(iatt),attvalue(iatt))
          enddo
        enddo

        ierr = nf90_close(ncid)

!       ierr = nf90_open(trim(joinfile),nf90_write,ncid)

!       record = 1
!       startr = (/record,1,1,1/)
!       allocate(var3d(1,1,1))
!       var3d = 0
       
!       call ncwrite(ncid,vname,var3d,startr)
!       ierr = nf90_close(ncid)
!       print *,'Closing joined file'
      endif ! mynode==0

      ierr = nf90_close(npid)

      end subroutine make_joined_file !]
! ----------------------------------------------------------------------
      subroutine write_joined_file ![
      ! read data for each variable in partial files
      ! and write to joinedl file, for all records
      implicit none

      ! local
      integer :: ierr, ncid,npid,dimid
      integer,dimension(4) :: llidx
      integer :: nx,ny,nxu,nyv,nz
      integer,dimension(:),allocatable :: i0,j0
      integer,dimension(:),allocatable :: i1,j1
      integer,dimension(:),allocatable :: i0u,i1u
      integer,dimension(:),allocatable :: j0v,j1v
      integer :: lnx,lny,li0,li1,lj0,lj1,li0u,li1u,lj0v,lj1v
      real,dimension(:,:,:),allocatable :: var3d
      character(len=30) :: vname
      type(ncstructure)  :: ncinfo
      integer,dimension(:),allocatable :: is,ie,js,je


      integer :: varid,ivar
      integer :: record,nrecords
      integer,dimension(4) :: startr,startw
      real,dimension(:),allocatable :: var1d
      integer :: sz1,sz2,sz3,ndims
      integer :: RSS


      ! get info about variables from first partial file in range

      ! Read partial files in range
      allocate(i0(part0:part1))
      allocate(j0(part0:part1))
      allocate(i1(part0:part1))
      allocate(j1(part0:part1))
      allocate(i0u(part0:part1))
      allocate(i1u(part0:part1))
      allocate(j0v(part0:part1))
      allocate(j1v(part0:part1))

      allocate(is(part0:part1))
      allocate(js(part0:part1))
      allocate(ie(part0:part1))
      allocate(je(part0:part1))

      do part = part0,part1  ! zero based ![
    
        partfile = partfiles(part)

        ierr = nf90_open(trim(adjustl(partfile)),nf90_write,npid)
        if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'opening file: ',trim(partfile) )

        if (part.eq.part0) call get_nc_info(npid, ncinfo) 

        ierr = nf90_get_att(npid,nf90_global,'start_idx',llidx)
        i0(part) = llidx(1)
        j0(part) = llidx(2)
        i0u(part)= llidx(3)
        j0v(part)= llidx(4)

        ierr = nf90_inq_dimid(npid,'xi_rho',dimid)
        if (ierr/=0) call handle_ierr(ierr,'getting dimid: ','xi_rho')
        ierr = nf90_inquire_dimension(npid, dimid, len=nx)
        if (ierr/=0) call handle_ierr(ierr,'getting dimension: ','xi_rho')

        ierr = nf90_inq_dimid(npid,'eta_rho',dimid)
        if (ierr/=0) call handle_ierr(ierr,'getting dimid: ','eta_rho')
        ierr = nf90_inquire_dimension(npid, dimid, len=ny)
        if (ierr/=0) call handle_ierr(ierr,'getting dimension: ','eta_rho')

        i1(part) = i0(part) + nx - 1
        j1(part) = j0(part) + ny - 1

        ! only if there is a u-variable in the file
        ierr = nf90_inq_dimid(npid,'xi_u',dimid)
        if (ierr/=0) call handle_ierr(ierr,'getting dimid: ','xi_u')
        ierr = nf90_inquire_dimension(npid, dimid, len=nxu)
        if (ierr/=0) call handle_ierr(ierr,'getting dimension: ','xi_u')
        i1u(part) = i0u(part) + nxu - 1

        ! only if there is a v-variable in the file
        ierr = nf90_inq_dimid(npid,'eta_v',dimid)
        if (ierr/=0) call handle_ierr(ierr,'getting dimid: ','eta_v')
        ierr = nf90_inquire_dimension(npid, dimid, len=nyv)
        if (ierr/=0) call handle_ierr(ierr,'getting dimension: ','eta_v')
        j1v(part) = j0v(part) + nyv - 1

        ! only if there is a 3d rho-variable in the file

        ierr = nf90_inq_dimid(npid,'s_rho',dimid)
        if (ierr/=0) call handle_ierr(ierr,'getting dimid: ','s_rho')
        ierr = nf90_inquire_dimension(npid, dimid, len=nz)
        if (ierr/=0) call handle_ierr(ierr,'getting dimension: ','s_rho')

        ierr = nf90_close(ncid)

      enddo ! part=part0,part1  !]


      li0 = minval(i0)
      li1 = maxval(i1)
      lj0 = minval(j0)
      lj1 = maxval(j1)
      li0u = minval(i0u)
      li1u = maxval(i1u)
      lj0v = minval(j0v)
      lj1v = maxval(j1v)
      lnx = li1 - li0 + 1
      lny = lj1 - lj0 + 1

      do record = 1,ncinfo%nrecords

        if (mynode==0) print *,'Processing record: ',record

        do ivar=1,ncinfo%nvars

          vname = ncinfo%varname(ivar)
          if (mynode==0) print *,'Processing: ',trim(vname)

            ndims = ncinfo%ndims(ivar)

        if (ncinfo%varpart(ivar)) then
          select case(ndims)
          case(1)
            ! save for later
          case(2)
            ! save for later (not present in pachug_rst.nc)
          case(3)
            if (index(ncinfo%dims(ivar)%dimnames(3),'time')>0) then
              select case(ncinfo%vartype(ivar))
              case('r')
                allocate(var3d(li0:li1,lj0:lj1,1))
                startr = (/li0,lj0,record,1/)
                is = i0; ie = i1
                js = j0; je = j1
              case('u')
                allocate(var3d(li0u:li1u,lj0:lj1,1))
                startr = (/li0u,lj0,record,1/)
                is = i0u; ie = i1u
                js = j0; je = j1
              case('v')
                allocate(var3d(li0:li1,lj0v:lj1v,1))
                startr = (/li0,lj0v,record,1/)
                is = i0; ie = i1
                js = j0v; je = j1v
              end select
              startw = (/1,1,record,1/)
            else
              if (record>1) continue
            ! save for later (not present in pachug_rst.nc)
            endif
          case(4)
              select case(ncinfo%vartype(ivar))
              case('r')
                allocate(var3d(li0:li1,lj0:lj1,nz))
                startr = (/li0,lj0,1,record/)
                is = i0; ie = i1
                js = j0; je = j1
              case('u')
                allocate(var3d(li0u:li1u,lj0:lj1,nz))
                startr = (/li0u,lj0,1,record/)
                is = i0u; ie = i1u
                js = j0; je = j1
              case('v')
                allocate(var3d(li0:li1,lj0v:lj1v,nz))
                startr = (/li0,lj0v,1,record/)
                is = i0; ie = i1
                js = j0v; je = j1v
              end select
              startw = (/1,1,1,record/)
          end select
        else
          select case(ndims)
          case(1)
            if (index(ncinfo%dims(ivar)%dimnames(1),'time')>0) then
              startr = (/record,1,1,1/)
              startw = (/record,1,1,1/)
              allocate(var3d(1,1,1))
              is = 1; ie = 1
              js = 1; je = 1
            else
              if (record>1) continue
              startr = (/1,1,1,1/)
              startw = (/1,1,1,1/)
              sz1 = ncinfo%dims(ivar)%dimsizes(1)
              allocate(var3d(sz1,1,1))
              is = 1; ie = sz1
              js = 1; je = 1
            endif
          case(2)
            if (index(ncinfo%dims(ivar)%dimnames(2),'time')>0) then
              startr = (/1,record,1,1/)
              startw = (/1,record,1,1/)
              sz1 = ncinfo%dims(ivar)%dimsizes(1)
              allocate(var3d(sz1,1,1))
              is = 1; ie = sz1
              js = 1; je = 1
            else
              if (record>1) continue
              startr = (/1,1,1,1/)
              startw = (/1,1,1,1/)
              sz1 = ncinfo%dims(ivar)%dimsizes(1)
              sz2 = ncinfo%dims(ivar)%dimsizes(2)
              allocate(var3d(sz1,sz2,1))
              is = 1; ie = sz1
              js = 1; je = sz2
            endif
          end select

        endif

        call system_mem_usage(RSS)
        print * ,'Mem usage 1: ', vname,'  ',RSS/1000

        print *, li0,li1,lj0,lj1
        var3d = 0

        do part = part0,part1  ! zero based
          partfile = partfiles(part)
          ierr = nf90_open(trim(partfile), nf90_nowrite, npid)
          call ncread(npid,vname,var3d(is(part):ie(part),js(part):je(part),:),startw)
          ierr = nf90_close(npid)
        enddo

        call system_mem_usage(RSS)
        print * ,'Mem usage 2: ', vname,'  ',RSS/1000

        ierr = nf90_open_par(trim(joinfile),nf90_write,part_comm,MPI_Info_Null, ncid)
        ierr = nf90_var_par_access(ncid, ivar, nf90_collective)
!       ierr = nf90_open(trim(joinfile),nf90_write,ncid)
        if (ierr/=nf90_noerr) 
     &    call handle_ierr(ierr,'opening file: ',trim(joinfile) )
        call ncwrite(ncid,vname,var3d,startr)
        ierr = nf90_close(ncid)

        call system_mem_usage(RSS)
        print * ,'Mem usage 3: ', vname,'  ',RSS/1000

        deallocate(var3d)

        call system_mem_usage(RSS)
        print * ,'Mem usage 4: ', vname,'  ',RSS/1000

!       print *,'mynode: ', mynode
      enddo  ! ivars

      enddo ! records
      ierr = nf90_close(ncid)

      deallocate(i0)
      deallocate(i1)
      deallocate(j0)
      deallocate(j1)

      end subroutine write_joined_file !]
! ----------------------------------------------------------------------
      subroutine get_nc_info(ncid, ncinfo)  ![

      implicit none        
        
      ! input/output
      integer,           intent(in)  :: ncid
      type(ncstructure), intent(out) :: ncinfo

      ! local
      character(len=20) :: attname
      character(len=200):: attvalue
      character(len=7) :: dname
      character(len=32) :: vname
      character(len=32), allocatable, dimension(:) :: dnames
      integer :: ierr, ivar, i, nvars, ndims, len, xtype,natts,dsize,nrecords
      integer :: dimid
      integer,dimension(5) :: dimids

      ierr = nf90_inq_dimid(ncid,'time',dimid)
       if (ierr /= nf90_noerr) call handle_ierr(ierr)
      ierr = nf90_inquire_dimension(ncid,dimid,len=nrecords)
       if (ierr /= nf90_noerr) call handle_ierr(ierr)
      ncinfo%nrecords = nrecords

      ! local allocation
      ierr = nf90_inquire(ncid,nvariables=nvars)

      ncinfo%nvars = nvars
      allocate(ncinfo%varname(nvars))
      allocate(ncinfo%vartype(nvars))
      allocate(ncinfo%varpart(nvars))
      allocate(ncinfo%xtype(nvars))
      allocate(ncinfo%ndims(nvars))
      allocate(ncinfo%dims(nvars))
      allocate(ncinfo%natts(nvars))
      allocate(ncinfo%atts(nvars))

      allocate(dnames(ndims))
      ncinfo%varpart = .false.

      ! append info to allocated arrays apart of derived type
      do ivar = 1,nvars
        
        ! Get information per variable
        ierr = nf90_inquire_variable(ncid,ivar,vname,xtype,ndims,dimids,natts)
        
        ! name of variable
        ncinfo%varname(ivar) = vname

        ! variable type
        ncinfo%xtype(ivar) = xtype

        ! r,u,v, or s (skip)
        ncinfo%vartype(ivar) = 'r'

        ! dimensions
        ncinfo%ndims(ivar) = ndims
        allocate(ncinfo%dims(ivar)%dimsizes(ndims))
        allocate(ncinfo%dims(ivar)%dimnames(ndims))
        do i = 1,ndims
          ierr = nf90_inquire_dimension(ncid,dimids(i),dname,dsize)
          ncinfo%dims(ivar)%dimnames(i) = dname
          ncinfo%dims(ivar)%dimsizes(i) = dsize
          if (index(dname,'xi_')>0 .or. index(dname,'eta_')>0) then
            ncinfo%varpart(ivar) = .true.
          endif
          if (index(dname,'eta_u')>0 ) then
            ncinfo%dims(ivar)%dimnames(i) = 'eta_rho'
          endif
          if (index(dname,'xi_v')>0 ) then
            ncinfo%dims(ivar)%dimnames(i) = 'xi_rho'
          endif
          if (index(dname,'xi_u')>0 ) then
            ncinfo%vartype(ivar) = 'u'
          endif
          if (index(dname,'eta_v')>0) then
            ncinfo%vartype(ivar) = 'v'
          endif
        enddo

        ! attributes
        ncinfo%natts(ivar) = natts
        allocate(ncinfo%atts(ivar)%attnames(natts))
        allocate(ncinfo%atts(ivar)%attvalues(natts))
        do i = 1,natts
          ierr = nf90_inq_attname(ncid,ivar,i,attname)
          ierr = nf90_get_att(ncid,ivar,attname,attvalue)
          ncinfo%atts(ivar)%attnames(i) = attname
          ncinfo%atts(ivar)%attvalues(i) = attvalue
        enddo
        
      enddo

      end subroutine get_nc_info !]
! ----------------------------------------------------------------------
      subroutine system_mem_usage(valueRSS) ![

      use ifport !if on intel compiler

      implicit none
      integer, intent(out) :: valueRSS

      character(len=200) :: filename = ' '
      character(len=80)  :: line
      character(len=8)   :: pid_char = ' '
      integer            :: pid
      logical            :: ifxst
      integer            :: ios

      valueRSS = -1    ! return negative number if not found

      !--- get process ID
      pid = getpid()
      write(pid_char, '(I8)') pid
      filename = '/proc/' // trim(adjustl(pid_char)) // '/status'

      !--- read system file
      inquire(file = filename, exist = ifxst)
      if (.not. ifxst) then
        write (*,*) 'system file does not exist'
        return
      endif

      open(unit = 100, file = filename, action = 'read')
      do
        read(100, '(a)', iostat=ios) line
        if (ios /= 0) then
          print *, 'error in RSS calc.'
          exit
        endif
        if (line(1:6) .eq. 'VmRSS:') then
          read(line(7:), *) valueRSS
          exit  ! Exit loop when VmRSS line is found
        endif
      enddo
      close(100)

      end subroutine system_mem_usage !]
! ----------------------------------------------------------------------
      logical function findstr(string,pattern,istart) ![
      implicit none

      !input/output
      character(len=*),intent(in)  :: string        ! string
      character(len=*),intent(in)  :: pattern       ! desired pattern to find within string
      integer,optional,intent(out) :: istart

      !local
      integer :: nl,nlv,i

      nl  = len(trim(string))
      nlv = len(pattern)

      findstr = .false.
      do i = 1,nl-nlv+1
         if (string(i:i+nlv-1) == pattern) then
          findstr = .true.
          exit
         endif
      enddo

      if (present(istart)) then
        if (findstr) then
          istart=i                                  ! return string starting index
        else
          istart=0
        endif
      endif

      end function findstr !]
! ----------------------------------------------------------------------

      end module roms_join
