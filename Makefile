# You can set PYTHON and PYTHON_CONFIG to a specific python-config binary if you want to build
# against a specific version of Python.
ifndef PYTHON_CONFIG
	PYTHON_CONFIG := python-config
endif
ifndef PYTHON
	PYTHON := python
endif

CFLAGS := $(shell $(PYTHON_CONFIG) --cflags) -fPIC
PYTHON_VERSION := $(shell ${PYTHON} -c 'import sysconfig; print(sysconfig.get_config_var("VERSION"))')
# Add --embed on Python 3.8; see https://docs.python.org/3/whatsnew/3.8.html#debug-build-uses-the-same-abi-as-release-build
PYTHON_CONFIG_EXTRA_FLAGS := $(shell if [ "${PYTHON_VERSION}" = "3.8" ] ; then echo --embed ; fi )
# Get Python LDFLAGS for our use, but remove macOS Python's -stack_size configuration, since it only applies to executables.
LDFLAGS := $(shell $(PYTHON_CONFIG) --ldflags ${PYTHON_CONFIG_EXTRA_FLAGS} | sed 'sX-Wl,-stack_size,1000000XXg')
LOWERCASE_OS := $(shell uname -s | tr '[A-Z]' '[a-z]')

# You can set JAVA_HOME to the path to your desired JVM. Otherwise we check /usr/libexec/java_home or the path to javac.
ifndef JAVA_HOME
	# This `wildcard` usage is true if the file does not exist. `ifneq` on top of that checks for file existence.
	ifneq ($(wildcard /usr/libexec/java_home),)
		JAVA_HOME := $(shell /usr/libexec/java_home)
	else
		JAVA_HOME := $(shell realpath $(shell dirname $(shell realpath $(shell which javac) ))/.. )
	endif
endif
JAVA_PLATFORM := $(JAVA_HOME)/include/$(LOWERCASE_OS)
JAVAC := $(JAVA_HOME)/bin/javac

ifeq ($(LOWERCASE_OS),linux)
	SOEXT := so
	# This is based on how PYTHON_LDVERSION is computed in the python3.x-config script bundled with Python.
	# We implement it here rather than calling python3.x-config because there is no way to ask python3.x-config
	# to provide just this value.
	PYTHON_ABIFLAGS := $(shell ${PYTHON} -c 'import sysconfig; print(sysconfig.get_config_var("ABIFLAGS"))')
	PYTHON_LDVERSION := ${PYTHON_VERSION}${PYTHON_ABIFLAGS}
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
	gcc -shared -o $@ $< $(LDFLAGS)

test: all
	java org.beeware.rubicon.test.Test

clean:
	rm -f org/beeware/rubicon/test/*.class
	rm -f org/beeware/rubicon/*.class
	rm -f jni/*.o
	rm -rf dist

%.class : %.java
	$(JAVAC) $<

%.o : %.c
	gcc -c $(CFLAGS) -Isrc -I$(JAVA_HOME)/include -I$(JAVA_PLATFORM) -o $@ $<
