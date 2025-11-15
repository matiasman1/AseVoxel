# Makefile for AseVoxel Native Shaders
# Alternative to CMake for simple builds

# Detect OS
UNAME_S := $(shell uname -s)

# Compiler settings
CXX := g++
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -fPIC -I..
LDFLAGS := -shared

# Platform-specific settings
ifeq ($(UNAME_S),Linux)
    EXT := .so
    LDFLAGS += -Wl,-soname,
endif
ifeq ($(UNAME_S),Darwin)
    EXT := .dylib
    LDFLAGS := -dynamiclib -install_name @rpath/
endif
ifeq ($(OS),Windows_NT)
    EXT := .dll
    LDFLAGS := -shared -Wl,--export-all-symbols
endif

# Output directory
OUTDIR := ../../bin
$(shell mkdir -p $(OUTDIR))

# Shader targets
SHADERS := \
	$(OUTDIR)/libnative_shader_basic$(EXT) \
	$(OUTDIR)/libnative_shader_dynamic$(EXT)

# Loader library
LOADER := $(OUTDIR)/libnative_shader_loader.a

# Test executable
TEST := $(OUTDIR)/test_host_shim

# Default target
all: $(SHADERS) $(LOADER) $(TEST)
	@echo "✓ All targets built successfully"
	@echo "  Shaders: $(OUTDIR)/libnative_shader_*$(EXT)"
	@echo "  Loader:  $(LOADER)"
	@echo "  Test:    $(TEST)"
	@ls -lh $(OUTDIR)/libnative_shader_*$(EXT) $(LOADER) $(TEST)

# Basic Lighting Shader
$(OUTDIR)/libnative_shader_basic$(EXT): basic_lighting_shader.cpp ../native_shader_api.h
	@echo "Building $@..."
	$(CXX) $(CXXFLAGS) $(LDFLAGS)$@ $< -o $@

# Dynamic Lighting Shader
$(OUTDIR)/libnative_shader_dynamic$(EXT): dynamic_lighting_shader.cpp ../native_shader_api.h
	@echo "Building $@..."
	$(CXX) $(CXXFLAGS) $(LDFLAGS)$@ $< -o $@

# Loader library (static lib)
$(LOADER): native_shader_loader.cpp native_shader_loader.hpp ../native_shader_api.h
	@echo "Building loader library..."
	$(CXX) $(CXXFLAGS) -c native_shader_loader.cpp -o /tmp/native_shader_loader.o
	ar rcs $@ /tmp/native_shader_loader.o
	@rm -f /tmp/native_shader_loader.o

# Test host shim (executable)
/tmp/stb_impl.o: stb_image_write_impl.cpp stb_image_write_real.h
	@echo "Compiling stb_image_write implementation..."
	$(CXX) $(CXXFLAGS) -I. -c stb_image_write_impl.cpp -o /tmp/stb_impl.o

$(TEST): test_host_shim.cpp /tmp/stb_impl.o $(LOADER) native_shader_loader.hpp ../native_shader_api.h
	@echo "Building test executable..."
	$(CXX) $(CXXFLAGS) -I. -rdynamic test_host_shim.cpp /tmp/stb_impl.o $(LOADER) -ldl -o $@

# Clean build artifacts
clean:
	rm -f $(SHADERS) $(LOADER) $(TEST)
	@echo "✓ Cleaned build artifacts"

# Test build (compile but don't link, for syntax checking)
test:
	$(CXX) $(CXXFLAGS) -c basic_lighting_shader.cpp -o /tmp/test_basic.o
	# (dominant_face removed)
	@echo "✓ Syntax check passed"
	rm -f /tmp/test_basic.o /tmp/test_dominant.o

# Show build info
info:
	@echo "Platform: $(UNAME_S)"
	@echo "Extension: $(EXT)"
	@echo "Compiler: $(CXX)"
	@echo "Flags: $(CXXFLAGS)"
	@echo "Linker: $(LDFLAGS)"
	@echo "Output: $(OUTDIR)"

.PHONY: all clean test info
