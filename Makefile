# Optionally read PYTHON_CONFIG from the environment to support building against a
# specific version of Python.
ifndef PYTHON_CONFIG
	PYTHON_CONFIG := python-config
endif

# Optionally read C compiler from the environment.
ifndef CC
	CC := gcc
endif

# Compute Python version + ABI suffix string by looking for the embeddable library name from the
# output of python-config. This way, we avoid executing the Python interpreter, which helps us
# in cross-compile contexts (e.g., Python built for Android).
PYTHON_LDVERSION := $(shell ($(PYTHON_CONFIG) --libs || true 2>&1 ) | cut -d ' ' -f1 | grep python | sed s,-lpython,, )
PYTHON_CONFIG_EXTRA_FLAGS := ""
# If that didn't give us a Python library name, then we're on Python 3.8 or higher, and we have to pass --embed.
# See https://docs.python.org/3/whatsnew/3.8.html#debug-build-uses-the-same-abi-as-release-build
ifndef PYTHON_LDVERSION
	PYTHON_CONFIG_EXTRA_FLAGS := "--embed"
	PYTHON_LDVERSION := $(shell ($(PYTHON_CONFIG) --libs ${PYTHON_CONFIG_EXTRA_FLAGS} || true 2>&1 ) | cut -d ' ' -f1 | grep python | sed s,-lpython,, )
endif

PYTHON_VERSION := $(shell echo ${PYTHON_LDVERSION} | sed 's,[^0-9.],,g')

# Use CFLAGS and LDFLAGS based on Python's. We add -fPIC since we're creating a shared library,
# and we remove -stack_size (only seen on macOS), since it only applies to executables.
CFLAGS := $(shell $(PYTHON_CONFIG) --cflags) -fPIC
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
	$(JAVAC) $<

%.o : %.c
	$(CC) -c $(CFLAGS) -Isrc -I$(JAVA_HOME)/include -I$(JAVA_PLATFORM) -o $@ $<
