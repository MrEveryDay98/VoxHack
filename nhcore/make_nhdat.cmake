# Builds the nhdat370 DLB archive from a staged dat directory.
# -DDLB=<dlb.exe> -DDAT=<staged dat dir> -DOUT=<archive path>
set(files data oracles options porthelp rumors help hh cmdhelp keyhelp
    history opthelp optmenu wizhelp license engrave epitaph bogusmon tribute)
file(GLOB luas RELATIVE "${DAT}" "${DAT}/*.lua")
list(APPEND files ${luas})
list(JOIN files "\n" content)
file(WRITE "${DAT}/dlb.lst" "${content}\n")
execute_process(COMMAND "${DLB}" CcIf "${DAT}" dlb.lst "${OUT}"
                RESULT_VARIABLE rv)
if(NOT rv EQUAL 0)
    message(FATAL_ERROR "dlb failed: ${rv}")
endif()
