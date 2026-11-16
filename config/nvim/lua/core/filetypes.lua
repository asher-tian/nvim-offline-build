vim.filetype.add({
    extension = {
        csh = "csh",
        tcl = "tcl",
        tm = "tcl",
        itcl = "tcl",
        tk = "tcl",
        tcsh = "csh",
        icl = "icl",
    },
    filename = {
        [".cshrc"] = "csh",
        [".tcshrc"] = "csh",
        [".login"] = "csh",
        [".logout"] = "csh",
    },
})
