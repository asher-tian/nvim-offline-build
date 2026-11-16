vim.filetype.add({
    extension = {
        csh = "csh",
        tcsh = "csh",
    },
    filename = {
        [".cshrc"] = "csh",
        [".tcshrc"] = "csh",
        [".login"] = "csh",
        [".logout"] = "csh",
    },
})
