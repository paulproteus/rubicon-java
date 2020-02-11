# You can set PYTHON_CONFIG to a specific python-config binary if you want to build
# against a specific version of Python.
ifndef PYTHON_CONFIG
	PYTHON_CONFIG := python-config
endif

# You can set CC to a specific binary if you want to e.g. cross-compile.
ifndef CC
	CC := gcc
endif

# Compute Python version + ABI suffix string by looking for the embeddable library name from the
# output of python-config. This way, we avoid executing the Python interpreter, which helps us
# in cross-compile contexts (e.g., Python built for Android).
PYTHON_LDVERSION := $(shell ($(PYTHON_CONFIG) --libs || true 2>&1 ) | cut -d ' ' -f1 | grep python | sed s,-lpython,, )
# If that didn't give us a Python library name, then we're on Python 3.8 or higher, and we have to pass --embed.
# See https://docs.python.org/3/whatsnew/3.8.html#debug-build-uses-the-same-abi-as-release-build
ifndef PYTHON_LDVERSION
	PYTHON_LDVERSION := $(shell ($(PYTHON_CONFIG) --libs --embed || true 2>&1 ) | cut -d ' ' -f1 | grep python | sed s,-lpython,, )
endif

PYTHON_VERSION := $(shell echo ${PYTHON_LDVERSION} | sed 's,[^0-9.],,g')

# Get Python CFLAGS & LDFLAGS for our use. Complications:
# - Remove macOS Python's -stack_size configuration, since it only applies to executables.
# - Pass --embed to python-config --ldflags on Python 3.8.
CFLAGS := $(shell $(PYTHON_CONFIG) --cflags) -fPIC
PYTHON_CONFIG_EXTRA_FLAGS := $(shell if [ "${PYTHON_VERSION}" = "3.8" ] ; then echo --embed ; fi )
LDFLAGS := $(shell $(PYTHON_CONFIG) --ldflags ${PYTHON_CONFIG_EXTRA_FLAGS} | sed 'sX-Wl,-stack_size,1000000XXg')

ifdef JAVA_HOME
	JAVAC := $(JAVA_HOME)/bin/javac
else
	JAVAC := $(shell which javac)
	ifeq ($(wildcard /usr/libexec/java_home),)
		JAVA_HOME := $(shell realpath $(JAVAC))
	else
		JAVA_HOME := $(shell /usr/libexec/java_home)
	endif
endif

# Rely on the current operating system to decide which JNI headers to use, and
# for one Python flag. At the moment, this means that Android builds of rubicon-java
# must be done on a Linux host.
LOWERCASE_OS := $(shell uname -s | tr '[A-Z]' '[a-z]')
JAVA_PLATFORM := $(JAVA_HOME)/include/$(LOWERCASE_OS)
ifeq ($(LOWERCASE_OS),linux)
	SOEXT := so
	# On Linux, including Android, Python extension modules require that `rubicon-java` dlopen() libpython.so with RTLD_GLOBAL.
	# Pass enough information here to allow that to happen.
	CFLAGS += -DLIBPYTHON_RTLD_GLOBAL=\"libpython${PYTHON_LDVERSION}.so\"
else ifeq ($(LOWERCASE_OS),darwin)
	SOEXT := dylib
endif

all: dist/rubicon.jar dist/librubicon.$(SOEXT) dist/test.jar

dist/rubicon.jar: org/beeware/rubicon/Python.class org/beeware/rubicon/PythonInstance.class
	mkdir -p dist
	jar -cvf dist/rubicon.jar org/beeware/rubicon/Python.class org/beeware/rubicon/PythonInstance.class

dist/test.jar: org/beeware/rubicon/test/BaseExample.class org/beeware/rubicon/test/Example.class org/beeware/rubicon/test/ICallback.class org/beeware/rubicon/test/AbstractCallback.class org/beeware/rubicon/test/Thing.class org/beeware/rubicon/test/Test.class
	mkdir -p dist
	jar -cvf dist/test.jar org/beeware/rubicon/test/*.class

dist/librubicon.$(SOEXT): jni/rubicon.o
	mkdir -p dist
	$(CC) -shared -o $@ $< $(LDFLAGS)

test: all
	java org.beeware.rubicon.test.Test

clean:
	rm -f org/beeware/rubicon/test/*.class
	rm -f org/beeware/rubicon/*.class
	rm -f jni/*.o
	rm -rf dist

%.class : %.java
	$(JAVAC) -source 1.8 -target 1.8 $<

%.o : %.c
	$(CC) -c $(CFLAGS) -Isrc -I$(JAVA_HOME)/include -I$(JAVA_PLATFORM) -o $@ $<
