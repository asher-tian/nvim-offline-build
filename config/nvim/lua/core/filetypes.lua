vim.filetype.add({
    extension = {
        csh = "csh",
        tcl = "tcl",
        tm = "tcl",
        itcl = "tcl",
        tk = "tcl",
        tcsh = "csh",
    },
    filename = {
        [".cshrc"] = "csh",
        [".tcshrc"] = "csh",
        [".login"] = "csh",
        [".logout"] = "csh",
    },
})
