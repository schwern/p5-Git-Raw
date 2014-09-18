MODULE = Git::Raw			PACKAGE = Git::Raw::Stash

SV *
save(class, repo, stasher, msg, ...)
	SV *class
	Repository repo
	Signature stasher
	SV *msg

	PROTOTYPE: $$$$;$

	PREINIT:
		int rc;

		git_oid oid;
		unsigned int stash_flags = GIT_STASH_DEFAULT;

	CODE:
		if (items == 5) {
			AV *flags;
			SV **flag;
			size_t i = 0, count = 0;

			flags = git_ensure_av(ST(4), "opts");

			while ((flag = av_fetch(flags, i++, 0))) {
				const char *opt = NULL;
				if (!SvPOK(*flag))
					continue;

				opt = SvPVbyte_nolen(*flag);

				if (strcmp(opt, "keep_index") == 0)
					stash_flags |= GIT_STASH_KEEP_INDEX;
				else if (strcmp(opt, "include_untracked") == 0)
					stash_flags |= GIT_STASH_INCLUDE_UNTRACKED;
				else if (strcmp(opt, "include_ignored") == 0)
					stash_flags |= GIT_STASH_INCLUDE_IGNORED;
				++count;
			}
		}

		rc = git_stash_save(&oid, repo -> repository, stasher, git_ensure_pv(msg, "msg"), stash_flags);
		if (rc == GIT_ENOTFOUND) {
			RETVAL = &PL_sv_undef;
		} else {
			git_check_error(rc);
			RETVAL = newSViv(1);
		}

	OUTPUT: RETVAL

void
foreach(class, repo, cb)
	SV *class
	SV *repo
	SV *cb

	PREINIT:
		int rc;

	CODE:
		git_foreach_payload payload = {
			GIT_SV_TO_PTR(Repository, repo),
			repo,
			cb
		};

		rc = git_stash_foreach(
			payload.repo_ptr -> repository, git_stash_foreach_cb, &payload
		);
		if (rc != GIT_EUSER)
			git_check_error(rc);

void
drop(class, repo, index)
	SV *class
	Repository repo
	size_t index

	PREINIT:
		int rc;

	CODE:
		rc = git_stash_drop(repo -> repository, index);
		git_check_error(rc);
