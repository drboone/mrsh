# Generated automatically from Makefile.in by configure.
# $Id: Makefile.in,v 1.7 2001/12/20 16:57:57 jettero Exp $

shell=/bin/bash

install_dir=/usr/local/bin
installed_owner=root
installed_group=bin
installed_perms=755

###############################################################################

name=mrsh
version=1.2.1
lname=${name}-${version}
ppacked=${lname}.tar
fpacked=${lname}.tar.gz

CCC=g++

CPPFLAGS=-DVERSION="\"${version}\"" -DBDATE="\"${DATESTR}\"" 

.SUFFIXES: .cpp .o

.cpp.o: 
	@${CCC} ${CPPFLAGS} -c $<
	@echo Compiling $*.o

headers=options.h machines.h options.h file.h

all:
	@make --no-print-directory real_all "DATESTR=`date '+%B %d, %Y'`"

real_all: ${name}

wpack: pack
	[ ${USER} = jettero ] && \
            mv ../${fpacked} /home/jettero/www/${name}/${fpacked}
pack:
	make clean
	cd ..; tar -cf ${ppacked} ${name}
	cd ..; gzip ${ppacked}
	cd ..; chmod 644 ${fpacked}

objs=options.o machines.o file.o ${name}.o

file.o:         file.cpp ${headers}
options.o:   options.cpp ${headers} defaults.h
machines.o: machines.cpp ${headers}
${name}.o:   ${name}.cpp ${headers}

${name}: ${objs}
	@$(CCC) -o ${name} ${objs}
	@echo Compiling ${name}

clean:
	@rm -vf ${name} *.o core fil

distclean: clean
	@rm -vf Makefile config.status config.log config.cache

install: all
	install -d -o ${installed_owner} -g ${installed_group} \
             -m ${installed_perms} ${install_dir}
	install -s -o ${installed_owner} -g ${installed_group} \
             -m ${installed_perms} ${name} ${install_dir}/${name}
	make clean
