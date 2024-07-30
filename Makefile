#**MakefileFile***********************************************************************
#
#  FileName    [Makefile]
#
#  Author      [Igor Melatti]
#
#  Copyright   [
#  This file contains the Makefile of toy CMurphi example.
#  Copyright (C) 2009-2012 by Sapienza University of Rome. 
#
#  CMurphi is free software; you can redistribute it and/or 
#  modify it under the terms of the GNU Lesser General Public 
#  License as published by the Free Software Foundation; either 
#  of the License, or (at your option) any later version.
#
#  CMurphi is distributed in the hope that it will be useful, 
#  but WITHOUT ANY WARRANTY; without even the implied warranty of 
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU 
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public 
#  License along with this library; if not, write to the Free Software 
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA.
#
#  To contact the CMurphi development board, email to <melatti@di.uniroma1.it>. ]
#
#*************************************************************************************

INCLUDEPATH = CMurphi/include
SRCPATH = CMurphi/src/

CXX = g++

CFLAGS = 

# optimization
#OFLAGS = -ggdb
OFLAGS = -O2
MEMGLUELITMUSTEST?=MemGlueMSI

#Murphi options
MURPHIOPTS = -b -c

all: ${MEMGLUELITMUSTEST}

# rules for compiling
${MEMGLUELITMUSTEST}: ${MEMGLUELITMUSTEST}.cpp
	${CXX} ${CFLAGS} ${OFLAGS} -o ${MEMGLUELITMUSTEST} ${MEMGLUELITMUSTEST}.cpp -I${INCLUDEPATH} -lm

# rules for C files
${MEMGLUELITMUSTEST}.cpp: ${MEMGLUELITMUSTEST}.m
	${SRCPATH}mu ${MURPHIOPTS} ${MEMGLUELITMUSTEST}.m

clean:
	rm -f *.cpp ${MEMGLUELITMUSTEST} 
