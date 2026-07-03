# copy_if_exists.cmake
# Copies SRC to DST only if SRC exists (non-fatal when source is missing).
# Usage: cmake -E env "SRC=..." "DST=..." cmake -P copy_if_exists.cmake

if(EXISTS "$ENV{SRC}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "$ENV{SRC}" "$ENV{DST}"
  )
endif()
