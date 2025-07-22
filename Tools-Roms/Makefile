#
.SUFFIXES: .o .f .F .f90

.F.o:
	@$(CPP) -P $*.F | mpc > $*.f
	$(FCOMP) -c $(FFLAGS) -o $*.o $*.f $(INCS)
	@/bin/rm -f $*.f
.F.f:
	$(CPP) -P  $*.F | mpc > $*.f
.f.o:
	$(FCOMP) -c $(FFLAGS) -o $*.o $*.f $(INCS)

     CPP = cpp -traditional

# Path names (non-hydrostatic & NetCDF libraries):

	NHMG_ROOT = $(ROMS_ROOT)/NHMG
	NHMG_INC  = -I$(NHMG_ROOT)/include
	NHMG_LIB  = -L$(NHMG_ROOT)/lib -lnhmg

	NETCDF_INC = -I$(NETCDF_ROOT)/include
	NETCDF_LIB = -L$(NETCDF_ROOT)/lib -lnetcdff
	NETCDFC_LIB = -L$(NETCDFC_ROOT)/lib -lnetcdf

	INCS = $(NETCDF_INC) $(NHMG_INC)
	LIBS = $(NHMG_LIB) $(NETCDF_LIB) $(NETCDFC_LIB)

# Fortran loader name and options: 
 	LDR = $(FCOMP)

# - Can't use -ip optimization for tools (partit won't compile)
	FFLAGS = -O3
# - uncomment for debugging:
#	FFLAGS = -g -fbacktrace -fcheck=all -ffpe-trap=invalid,zero,overflow

# OpenMP flags - needed for r2r_bry (and possibly others):
#	note, -qopenmp is the new -openmp but is still needed for maya
        OMP_FLAG = -qopenmp

# --------------------------------------------------------------------

ALL = partit ncjoin ncjoin_mpi extract_data_join nc3to4z zslice sample
#ALL = partit ncjoin_mpi extract_data_join nc3to4z
#r2r_bry r2r_match_topo r2r_init

all:	$(info MAKING ROMS TOOLS:) mpc $(ALL)

#install: $(ALL)
#	mv $(ALL) ~/bin

# Note: the following .f: dependencies are needed to make everything
# go through CPP and take custom defined CPPFLAGS rather than compiling
# executables from .F directly.

chkindent: chkindent.f

# The following two are built from the same source
# and differ only CPP macro setting:

mreplace.f: mreplace.F
	$(CPP) -P $(CPPFLAGS) -DREPLACE mreplace.F > mreplace.f
	
partit: partit.o insert_node.o lenstr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o partit partit.o insert_node.o lenstr.o $(LIBS)

ncjoin: ncjoin.o lenstr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o ncjoin ncjoin.o lenstr.o $(LIBS)	

simple_xy_par_wr: simple_xy_par_wr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o simple_xy_par_wr simple_xy_par_wr.o $(LIBS)	
	
ncjoin_mpi: ncjoin_mpi.opt ncjoin_mod.o ncjoin_mpi.o lenstr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o ncjoin_mpi ncjoin_mod.o ncjoin_mpi.o lenstr.o $(LIBS)
	
nc3to4z: nc3to4z.o lenstr.o read_string.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o nc3to4z nc3to4z.o lenstr.o read_string.o $(LIBS)
	
mpc: mpc.F Makefile
	$(CPP) $(CPPFLAGS) -P mpc.F > ./mpc.f
	$(FCOMP) $(FFLAGS) $(LDFLAGS) -o mpc ./mpc.f
	
extract_data_join: ncjoin_mod.o extract_data_join.o  lenstr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o extract_data_join ncjoin_mod.o extract_data_join.o lenstr.o  $(LIBS)
	
particle_join: ncjoin_mod.o particle_join.o  lenstr.o
	$(LDR) $(FFLAGS) $(LDFLAGS) -o particle_join ncjoin_mod.o particle_join.o lenstr.o  $(LIBS)

R2R_INIT = r2r_init.o r2r_interp_init.o r2r_subs.o r2r_rotate.o r2r_vert_interp.o\
           set_depth.o etch_into_land.o spln2d.o tiling.o roms_read_write.o\
           read_string.o lenstr.o

r2r_init: $(R2R_INIT)
	$(LDR) $(FFLAGS) $(LDFLAGS) -o r2r_init $(R2R_INIT) $(LIBS)

 R2R_BRY = r2r_bry.o r2r_bry_interp.o r2r_subs.o r2r_bry_rotate.o r2r_rotate.o\
           r2r_vert_interp.o set_depth.o etch_into_land.o spln2d.o tiling.o\
           def_bry_file.o roms_read_write.o read_string.o lenstr.o

r2r_bry: $(R2R_BRY)
	$(LDR) $(FFLAGS) $(LDFLAGS) -o r2r_bry $(R2R_BRY) $(LIBS)

 ZSLICE = zslice.o set_depth.o sigma_to_z_intr.o read_add_write.o\
	  roms_read_write.o read_string.o lenstr.o tiling.o

 IPSLICE = ipslice.o set_depth.o sigma_to_z_intr.o rho_eos.o\
	   read_add_write.o roms_read_write.o read_string.o lenstr.o tiling.o

 SAMPLE = roms_read_write.o sample.o tiling.o\
          read_add_write.o read_string.o lenstr.o

R2R_MATCH_TOPO = r2r_match_topo.o r2r_interp_init.o mrg_zone_subs.o tiling.o\
                        spln2d.o roms_read_write.o read_string.o lenstr.o
                        
r2r_match_topo: $(R2R_MATCH_TOPO)
	$(LDR) $(FFLAGS) $(LDFLAGS) -o r2r_match_topo $(R2R_MATCH_TOPO) $(LIBS)                                  
          
zslice: $(ZSLICE)
	$(LDR) $(FFLAGS) -o zslice $(ZSLICE) $(LIBS)

ipslice: $(IPSLICE)
	$(LDR) $(FFLAGS) -o ipslice $(IPSLICE) $(LIBS)

ipslice.f: zslice.F
	$(CPP) -P $(CPPFLAGS) -DIPSLICE zslice.F | ./mpc > ipslice.f

sample: $(SAMPLE)
	$(LDR) $(FFLAGS) -o sample $(SAMPLE) $(LIBS)

clean:
	/bin/rm -f *.f *.o *.a *.s *.trace *.mod

clobber: clean
	/bin/rm -f $(ALL) *.bak
	
include Make.depend
