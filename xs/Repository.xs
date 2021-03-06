MODULE = Git::Raw			PACKAGE = Git::Raw::Repository

Repository
init(class, path, is_bare)
	SV *class
	SV *path
	unsigned is_bare

	PREINIT:
		int rc;
		git_repository *r = NULL;
		Repository repo = NULL;

	CODE:
		rc = git_repository_init(
			&r, git_ensure_pv(path, "path"), is_bare
		);
		git_check_error(rc);

		Newxz(repo, 1, git_raw_repository);
		repo -> repository = r;
		repo -> owned = 1;

		RETVAL = repo;

	OUTPUT: RETVAL

Repository
clone(class, url, path, opts)
	SV *class
	SV *url
	SV *path
	HV *opts

	PREINIT:
		int rc;

		SV *opt;
		HV *callbacks;
		git_repository *r = NULL;
		Repository repo = NULL;

		SV *remote_cb = NULL;
		git_raw_remote_callbacks cbs = {0, 0, 0, 0};
		git_clone_options clone_opts = GIT_CLONE_OPTIONS_INIT;

	CODE:
		clone_opts.remote_callbacks.payload = &cbs;

		if ((opt = git_hv_int_entry(opts, "bare")) && SvIV(opt))
			clone_opts.bare = 1;

		if ((opt = git_hv_string_entry(opts, "checkout_branch")))
			clone_opts.checkout_branch = git_ensure_pv(opt, "checkout_branch");

		if ((opt = git_hv_int_entry(opts, "disable_checkout")) && SvIV(opt))
			clone_opts.checkout_opts.checkout_strategy = GIT_CHECKOUT_NONE;

		/* Callbacks */
		if ((callbacks = git_hv_hash_entry(opts, "callbacks"))) {
			/* Clone callbacks */
			if ((remote_cb = get_callback_option(callbacks, "remote_create"))) {
				clone_opts.remote_cb = git_remote_create_cbb;
				clone_opts.remote_cb_payload = remote_cb;
			}

			/* Remote callbacks */
			if ((cbs.credentials =
				get_callback_option(callbacks, "credentials")))
				clone_opts.remote_callbacks.credentials =
					git_credentials_cbb;

			if ((cbs.certificate_check =
				get_callback_option(callbacks, "certificate_check")))
				clone_opts.remote_callbacks.certificate_check =
					git_certificate_check_cbb;

			if ((cbs.progress =
				get_callback_option(callbacks, "sideband_progress")))
				clone_opts.remote_callbacks.sideband_progress =
					git_progress_cbb;

			if ((cbs.transfer_progress =
				get_callback_option(callbacks, "transfer_progress")))
				clone_opts.remote_callbacks.transfer_progress =
					git_transfer_progress_cbb;

			if ((cbs.update_tips =
				get_callback_option(callbacks, "update_tips")))
				clone_opts.remote_callbacks.update_tips =
					git_update_tips_cbb;
		}

		rc = git_clone(
			&r, git_ensure_pv(url, "url"), git_ensure_pv(path, "path"),
			&clone_opts
		);

		git_clean_remote_callbacks(&cbs);
		SvREFCNT_dec(remote_cb);
		git_check_error(rc);

		Newxz(repo, 1, git_raw_repository);
		repo -> repository = r;
		repo -> owned = 1;

		RETVAL = repo;

	OUTPUT: RETVAL

Repository
open(class, path)
	SV *class
	SV *path

	PREINIT:
		int rc;
		git_repository *r = NULL;
		Repository repo = NULL;

	CODE:
		rc = git_repository_open(&r, git_ensure_pv(path, "path"));
		git_check_error(rc);

		Newxz(repo, 1, git_raw_repository);
		repo -> repository = r;
		repo -> owned = 1;

		RETVAL = repo;

	OUTPUT: RETVAL

Repository
discover(class, path)
	SV *class
	SV *path

	PREINIT:
		int rc;

		git_repository *r = NULL;
		Repository repo = NULL;

	CODE:
		git_buf buf = GIT_BUF_INIT_CONST(NULL, 0);

		rc = git_buf_grow(&buf, GIT_PATH_MAX);
		git_check_error(rc);

		rc = git_repository_discover(
			&buf, git_ensure_pv(path, "path"), 1, NULL
		);

		if (rc == GIT_OK)
			rc = git_repository_open(&r, (const char*) buf.ptr);

		git_buf_free(&buf);
		git_check_error(rc);

		Newxz(repo, 1, git_raw_repository);
		repo -> repository = r;
		repo -> owned = 1;

		RETVAL = repo;

	OUTPUT: RETVAL

Repository
new(class)
	SV *class

	PREINIT:
		int rc;
		git_repository *r = NULL;
		Repository repo = NULL;

	CODE:
		rc = git_repository_new(&r);
		git_check_error(rc);

		Newxz(repo, 1, git_raw_repository);
		repo -> repository = r;
		repo -> owned = 1;

		RETVAL = repo;

	OUTPUT: RETVAL

Config
config(self)
	Repository self

	PREINIT:
		int rc;
		Config cfg;

	CODE:
		rc = git_repository_config(&cfg, self -> repository);
		git_check_error(rc);

		RETVAL = cfg;

	OUTPUT: RETVAL

SV *
index(self)
	SV *self

	PREINIT:
		int rc;
		Index index;

		Repository repo = NULL;

	CODE:
		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_repository_index(&index, repo -> repository);
		git_check_error(rc);

		GIT_NEW_OBJ_WITH_MAGIC(
			RETVAL, "Git::Raw::Index", index, SvRV(self)
		);

	OUTPUT: RETVAL

SV *
head(self, ...)
	SV *self

	PROTOTYPE: $;$$

	PREINIT:
		int rc;

		Reference head;
		Repository repo;
		Signature sig;

	CODE:
		repo = GIT_SV_TO_PTR(Repository, self);

		if (items >= 2) {
			const char *reflog_message = "reset";
			Reference new_head = GIT_SV_TO_PTR(Reference, ST(1));

			if (items >= 3)
				reflog_message = git_ensure_pv(ST(2), "message");

			rc = git_signature_default(&sig, repo -> repository);
			git_check_error(rc);

			rc = git_repository_set_head(
				repo -> repository, git_reference_name(new_head),
				sig, reflog_message
			);
			git_signature_free(sig);
			git_check_error(rc);
		}

		rc = git_repository_head(&head, repo -> repository);
		git_check_error(rc);

		GIT_NEW_OBJ_WITH_MAGIC(
			RETVAL, "Git::Raw::Reference", head, SvRV(self)
		);

	OUTPUT: RETVAL

void
detach_head(self, commitish, ...)
	SV *self
	SV *commitish

	PROTOTYPE: $$;$
	PREINIT:
		int rc;

		Repository repo;
		Signature sig;
		git_oid id;

		const char *reflog_message = "reset";

	CODE:
		if (items == 3)
			reflog_message = git_ensure_pv(ST(2), "message");

		repo = GIT_SV_TO_PTR(Repository, self);

		if (git_sv_to_commitish(repo -> repository, commitish, &id) == NULL)
			croak_resolve("Could not resolve 'commitish' to a commit id");

		rc = git_signature_default(&sig, repo -> repository);
		git_check_error(rc);

		rc = git_repository_set_head_detached(repo -> repository,
			&id, sig, reflog_message);
		git_check_error(rc);

SV *
lookup(self, id)
	SV *self
	SV *id

	PREINIT:
		int rc;

		git_oid oid;
		git_object *obj;

		STRLEN len;
		const char *id_str;

		Repository repo = NULL;

	CODE:
		id_str = git_ensure_pv_with_len(id, "id", &len);

		rc = git_oid_fromstrn(&oid, id_str, len);
		git_check_error(rc);

		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_object_lookup_prefix(
			&obj, repo -> repository, &oid, len, GIT_OBJ_ANY
		);

		if (rc == GIT_ENOTFOUND) {
			RETVAL = &PL_sv_undef;
		} else {
			git_check_error(rc);
			RETVAL = git_obj_to_sv(obj, SvRV(self));
		}

	OUTPUT: RETVAL

void
checkout(self, target, opts)
	Repository self
	SV *target
	HV *opts

	PREINIT:
		int rc;

		git_checkout_options checkout_opts = GIT_CHECKOUT_OPTIONS_INIT;

	CODE:
		git_hv_to_checkout_opts(opts, &checkout_opts);

		rc = git_checkout_tree(
			self -> repository, git_sv_to_obj(target), &checkout_opts
		);

		Safefree(checkout_opts.paths.strings);
		git_check_error(rc);

void
reset(self, target, opts)
	Repository self
	SV *target
	HV *opts

	PREINIT:
		int rc;

		Signature sig;
		SV *opt;
		AV *lopt;

	CODE:
		if ((lopt = git_hv_list_entry(opts, "paths"))) {
			SV **path;

			size_t i = 0, count = 0;
			git_strarray paths = {0, 0};

			while ((path = av_fetch(lopt, i++, 0))) {
				if (!SvOK(*path))
					continue;

				Renew(paths.strings, count + 1, char *);
				paths.strings[count++] = SvPVbyte_nolen(*path);
			}

			paths.count = count;

			rc = git_reset_default(self -> repository, git_sv_to_obj(target), &paths);
			Safefree(paths.strings);
			git_check_error(rc);
		} else if ((opt = git_hv_string_entry(opts, "type"))) {
			git_reset_t reset = GIT_RESET_SOFT;
			const char *type_str = SvPVbyte_nolen(opt);

			if (strcmp(type_str, "soft") == 0)
				reset = GIT_RESET_SOFT;
			else if (strcmp(type_str, "mixed") == 0)
				reset = GIT_RESET_MIXED;
			else if (strcmp(type_str, "hard") == 0)
				reset = GIT_RESET_HARD;
			else
				croak_usage("Invalid type '%s'. "
					"Valid values: 'soft', 'mixed' or 'hard'",
					type_str);

			rc = git_signature_default(&sig, self -> repository);
			git_check_error(rc);

			rc = git_reset(self -> repository, git_sv_to_obj(target), reset, NULL, sig, NULL);
			git_signature_free(sig);
			git_check_error(rc);
		}

HV *
status(self, opts, ...)
	Repository self
	HV *opts

	PROTOTYPE: $$;@

	PREINIT:
		int rc, i, count;

		SV *opt;
		HV *status_hv, *hopt;

		git_status_list *list;
		git_status_options status_opts = GIT_STATUS_OPTIONS_INIT;

	CODE:
		if ((hopt = git_hv_hash_entry(opts, "flags")))
			status_opts.flags = git_hv_to_status_flag(hopt);

		if ((opt = git_hv_string_entry(opts, "show"))) {
			const char *show_str = SvPVbyte_nolen(opt);

			if (strcmp(show_str, "index_and_worktree") == 0)
				status_opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
			else if (strcmp(show_str, "index") == 0)
				status_opts.show = GIT_STATUS_SHOW_INDEX_ONLY;
			else if (strcmp(show_str, "worktree") == 0)
				status_opts.show = GIT_STATUS_SHOW_WORKDIR_ONLY;
			else
				croak_usage("Invalid show value '%s'. "
					"Valid values: 'index_and_worktree', 'index' or 'worktree'",
					show_str);
		}

		if (items > 2) {
			Newx(status_opts.pathspec.strings, items - 2, char *);

			for (i = 2; i < items; i++) {
				size_t index = (size_t) i - 2;
				status_opts.pathspec.strings[index] =
					SvPVbyte_nolen(ST(i));
				status_opts.pathspec.count = index + 1;
			}
		}

		rc = git_status_list_new(&list, self -> repository, &status_opts);
		Safefree(status_opts.pathspec.strings);
		git_check_error(rc);

		count = (int) git_status_list_entrycount(list);

		status_hv = newHV();
		for (i = 0; i < count; i++) {
			AV *flags;
			HV *file_status_hv;

			const char *path = NULL;
			const git_status_entry *entry =
				git_status_byindex(list, i);

			flags = newAV();

			if (entry -> status & GIT_STATUS_INDEX_NEW)
				av_push(flags, newSVpv("index_new", 0));

			if (entry -> status & GIT_STATUS_INDEX_MODIFIED)
				av_push(flags, newSVpv("index_modified", 0));

			if (entry -> status & GIT_STATUS_INDEX_DELETED)
				av_push(flags, newSVpv("index_deleted", 0));

			if (entry -> status & GIT_STATUS_INDEX_RENAMED)
				av_push(flags, newSVpv("index_renamed", 0));

			if (entry -> status & GIT_STATUS_WT_NEW)
				av_push(flags, newSVpv("worktree_new", 0));

			if (entry -> status & GIT_STATUS_WT_MODIFIED)
				av_push(flags, newSVpv("worktree_modified", 0));

			if (entry -> status & GIT_STATUS_WT_DELETED)
				av_push(flags, newSVpv("worktree_deleted", 0));

			if (entry -> status & GIT_STATUS_WT_RENAMED)
				av_push(flags, newSVpv("worktree_renamed", 0));

			if (entry -> status & GIT_STATUS_WT_UNREADABLE)
				av_push(flags, newSVpv("worktree_unreadable", 0));

			if (entry -> status & GIT_STATUS_IGNORED)
				av_push(flags, newSVpv("ignored", 0));

			file_status_hv = newHV();

			if (entry -> index_to_workdir) {
				if (entry -> status & GIT_STATUS_WT_RENAMED) {
					HV *worktree_status_hv = newHV();

					hv_stores(worktree_status_hv, "old_file",
						newSVpv(entry -> index_to_workdir -> old_file.path, 0));
					hv_stores(file_status_hv, "worktree", newRV_noinc((SV *) worktree_status_hv));
				}

				path = entry -> index_to_workdir -> new_file.path;
			}

			if (entry -> head_to_index) {
				if (entry -> status & GIT_STATUS_INDEX_RENAMED) {
					HV *index_status_hv = newHV();

					hv_stores(index_status_hv, "old_file",
						newSVpv(entry -> head_to_index -> old_file.path, 0));
					hv_stores(file_status_hv, "index", newRV_noinc((SV *) index_status_hv));
				}

				if (!path)
					path = entry -> head_to_index -> new_file.path;
			}

			hv_stores(file_status_hv, "flags", newRV_noinc((SV *) flags));
			hv_store(status_hv, path, strlen(path), newRV_noinc((SV *) file_status_hv), 0);
		}

		git_status_list_free(list);

		RETVAL = status_hv;

	OUTPUT: RETVAL

SV *
path_is_ignored(self, path)
	Repository self
	const char *path

	PREINIT:
		int rc, ignore;

	CODE:
		rc = git_ignore_path_is_ignored(&ignore, self -> repository, path);
		git_check_error(rc);

		RETVAL = newSViv(ignore);

	OUTPUT: RETVAL

void
ignore(self, rules)
	Repository self
	SV *rules

	PREINIT:
		int rc;

	CODE:
		rc = git_ignore_add_rule(self -> repository, git_ensure_pv(rules, "rules"));
		git_check_error(rc);

Diff
diff(self, ...)
	Repository self

	PROTOTYPE: $;$

	PREINIT:
		int rc;

		Diff diff;
		Index index;

		Tree tree = NULL;

		git_diff_options diff_opts = GIT_DIFF_OPTIONS_INIT;

	CODE:
		rc = git_repository_index(&index, self -> repository);
		git_check_error(rc);

		if (items == 2) {
			HV *opts = git_ensure_hv(ST(1), "diff_opts");
			git_hv_to_diff_opts(opts, &diff_opts, &tree);
		}

		if (tree) {
			rc = git_diff_tree_to_index(
				&diff, self -> repository, tree, index, &diff_opts
			);
		} else {
			rc = git_diff_index_to_workdir(
				&diff, self -> repository, index, &diff_opts
			);
		}

		git_index_free(index);
		if (diff_opts.pathspec.count > 0)
			Safefree(diff_opts.pathspec.strings);
		git_check_error(rc);

		RETVAL = diff;

	OUTPUT: RETVAL

SV *
merge_base(repo, ...)
	SV *repo

	PROTOTYPE: $;@

	PREINIT:
		int i, rc, count;

		Repository repo_ptr;
		git_oid merge_base, *oids = NULL;

	CODE:
		if (items < 3)
			croak_usage("At least 2 arguments needed");

		repo_ptr = GIT_SV_TO_PTR(Repository, repo);

		count = items - 1;
		Renew(oids, count, git_oid);
		for (i = 0; i < count; ++i) {
			if (git_sv_to_commitish(repo_ptr -> repository, ST(i + 1), oids + i) == NULL) {
				Safefree(oids);
				croak_resolve("Could not resolve 'object' to a commit id");
			}
		}

		rc = git_merge_base_many(
			&merge_base, repo_ptr -> repository, (size_t) count, oids);
		Safefree(oids);

		RETVAL = &PL_sv_undef;
		if (rc != GIT_ENOTFOUND) {
			Commit commit;
			git_check_error(rc);

			rc = git_commit_lookup(&commit, repo_ptr -> repository, &merge_base);
			git_check_error(rc);

			GIT_NEW_OBJ_WITH_MAGIC(
				RETVAL, "Git::Raw::Commit",
				commit, repo
			);
		}

	OUTPUT: RETVAL

SV *
merge_analysis(self, ref)
	Repository self
	Reference ref

	PREINIT:
		int rc;

		git_merge_head *merge_head;
		git_merge_preference_t pref;
		git_merge_analysis_t analysis;

		AV *result;
	CODE:
		rc = git_merge_head_from_ref(&merge_head, self -> repository, ref);
		git_check_error(rc);

		rc = git_merge_analysis(&analysis, &pref,
			self -> repository, (const git_merge_head **) &merge_head, 1);
		git_merge_head_free(merge_head);
		git_check_error(rc);

		result = newAV();
		if (analysis & GIT_MERGE_ANALYSIS_NORMAL)
			av_push(result, newSVpv("normal", 0));
		if (analysis & GIT_MERGE_ANALYSIS_UP_TO_DATE)
			av_push(result, newSVpv("up_to_date", 0));
		if (analysis & GIT_MERGE_ANALYSIS_FASTFORWARD)
			av_push(result, newSVpv("fast_forward", 0));
		if (analysis & GIT_MERGE_ANALYSIS_UNBORN)
			av_push(result, newSVpv("unborn", 0));

		RETVAL = newRV_noinc((SV *) result);

	OUTPUT: RETVAL

void
merge(self, ref, ...)
	Repository self
	Reference ref

	PROTOTYPE: $$;$;$
	PREINIT:
		int rc;

		git_merge_head *merge_head;

		git_merge_options merge_opts = GIT_MERGE_OPTIONS_INIT;
		git_checkout_options checkout_opts = GIT_CHECKOUT_OPTIONS_INIT;

	CODE:
		rc = git_merge_head_from_ref(&merge_head, self -> repository, ref);
		git_check_error(rc);

		if (items >= 3) {
			HV *opts = git_ensure_hv(ST(2), "merge_opts");
			git_hv_to_merge_opts(opts, &merge_opts);
		}

		if (items >= 4) {
			HV *opts = git_ensure_hv(ST(3), "checkout_opts");
			git_hv_to_checkout_opts(opts, &checkout_opts);
		}

		rc = git_merge(
			self -> repository, (const git_merge_head **) &merge_head,
			1, &merge_opts, &checkout_opts
		);
		Safefree(checkout_opts.paths.strings);
		git_merge_head_free(merge_head);
		git_check_error(rc);

void
branches(self, ...)
	SV *self

	PROTOTYPE: $;$
	PREINIT:
		int rc;

		Branch branch;
		int num_branches = 0;

		git_branch_t type;
		git_branch_iterator *itr;

		Repository repo;

	PPCODE:
		type = GIT_BRANCH_ALL;

		if (items == 2) {
			const char *type_str = git_ensure_pv(ST(1), "type");

			if (strcmp(type_str, "local") == 0)
				type = GIT_BRANCH_LOCAL;
			else if (strcmp(type_str, "remote") == 0)
				type = GIT_BRANCH_REMOTE;
			else if (strcmp(type_str, "all") == 0)
				type = GIT_BRANCH_ALL;
			else
				croak_usage("Invalid branch type '%s'. ",
					"Valid values: 'local', 'remote' or 'all'",
					type_str);
		}

		repo = GIT_SV_TO_PTR(Repository, self);

		rc = git_branch_iterator_new(&itr, repo -> repository, type);
		git_check_error(rc);

		while ((rc = git_branch_next(&branch, &type, itr)) == 0) {
			SV *perl_ref;

			GIT_NEW_OBJ_WITH_MAGIC(
				perl_ref, "Git::Raw::Branch", branch, SvRV(self)
			);

			mXPUSHs(perl_ref);

			num_branches++;
		}

		git_branch_iterator_free(itr);
		git_check_error(rc);

		XSRETURN(num_branches);

void
remotes(self)
	SV *self

	PREINIT:
		int rc;
		size_t i;

		int num_remotes = 0;
		git_strarray remotes;

		Repository repo;

	PPCODE:
		repo = GIT_SV_TO_PTR(Repository, self);

		rc = git_remote_list(&remotes, repo -> repository);
		git_check_error(rc);

		for (i = 0; i < remotes.count; i++) {
			SV *perl_ref;
			git_remote *r = NULL;
			Remote remote = NULL;

			rc = git_remote_load(&r, repo -> repository, remotes.strings[i]);
			git_check_error(rc);

			Newxz(remote, 1, git_raw_remote);
			git_init_remote_callbacks(&remote -> callbacks);
			remote -> remote = r;

			GIT_NEW_OBJ_WITH_MAGIC(
				perl_ref, "Git::Raw::Remote", remote, SvRV(self)
			);

			mXPUSHs(perl_ref);

			num_remotes++;
		}

		git_strarray_free(&remotes);

		XSRETURN(num_remotes);

void
refs(self)
	SV *self

	PREINIT:
		int rc;

		Reference ref;
		int num_refs = 0;

		git_reference_iterator *itr;

		Repository repo = NULL;

	PPCODE:
		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_reference_iterator_new(&itr, repo -> repository);
		git_check_error(rc);

		while ((rc = git_reference_next(&ref, itr)) == 0) {
			SV *perl_ref;

			GIT_NEW_OBJ_WITH_MAGIC(
				perl_ref, "Git::Raw::Reference", ref, SvRV(self)
			);

			mXPUSHs(perl_ref);

			num_refs++;
		}

		git_reference_iterator_free(itr);
		git_check_error(rc);

		XSRETURN(num_refs);

SV *
path(self)
	Repository self

	PREINIT:
		const char *path;

	CODE:
		path = git_repository_path(self -> repository);
		RETVAL = newSVpv(path, 0);

	OUTPUT: RETVAL

SV *
workdir(self, ...)
	Repository self

	PROTOTYPE: $;$

	PREINIT:
		int rc;
		const char *path;

	CODE:
		if (items == 2) {
			const char *new_dir = git_ensure_pv(ST(1), "new_dir");

			rc = git_repository_set_workdir(self -> repository, new_dir, 1);
			git_check_error(rc);
		}

		path = git_repository_workdir(self -> repository);
		RETVAL = newSVpv(path, 0);

	OUTPUT: RETVAL

SV *
blame(self, file)
	SV *self
	const char *file

	PREINIT:
		int rc;
		Blame blame;

		Repository repo = NULL;
		git_blame_options options = GIT_BLAME_OPTIONS_INIT;

	CODE:
		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_blame_file(
			&blame, repo -> repository, file, &options);
		git_check_error(rc);

		GIT_NEW_OBJ_WITH_MAGIC(
			RETVAL, "Git::Raw::Blame", blame, SvRV(self)
		);

	OUTPUT: RETVAL

void
cherry_pick(self, commit, ...)
	SV *self
	Commit commit

	PROTOTYPE: $$;$;$;$
	PREINIT:
		int rc;

		Repository repo = NULL;
		git_cherrypick_options opts = GIT_CHERRYPICK_OPTIONS_INIT;

	CODE:
		if (items >= 3) {
			HV *hopts = git_ensure_hv(ST(2), "merge_opts");
			git_hv_to_merge_opts(hopts, &opts.merge_opts);
		}

		if (items >= 4) {
			HV *hopts = git_ensure_hv(ST(3), "checkout_opts");
			git_hv_to_checkout_opts(hopts, &opts.checkout_opts);
		}

		if (items >= 5) {
			unsigned int parents = git_commit_parentcount(commit);
			int mainline = git_ensure_iv(ST(4), "mainline");

			if (mainline < 0 || mainline > (int) git_commit_parentcount(commit) - 1)
				croak_usage("'mainline' out of range, should be between 0 and %d",
					(int) parents - 1);

			opts.mainline = (unsigned int) mainline;
		}

		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_cherrypick(
			repo -> repository,
			commit,
			&opts
		);
		git_check_error(rc);

void
revert(self, commit, ...)
	SV *self
	Commit commit

	PROTOTYPE: $$;$;$;$
	PREINIT:
		int rc;

		Repository repo = NULL;
		git_revert_options opts = GIT_REVERT_OPTIONS_INIT;

	CODE:
		if (items >= 3) {
			HV *hopts = git_ensure_hv(ST(2), "merge_opts");
			git_hv_to_merge_opts(hopts, &opts.merge_opts);
		}

		if (items >= 4) {
			HV *hopts = git_ensure_hv(ST(3), "checkout_opts");
			git_hv_to_checkout_opts(hopts, &opts.checkout_opts);
		}

		if (items >= 5) {
			unsigned int parents = git_commit_parentcount(commit);
			int mainline = git_ensure_iv(ST(4), "mainline");

			if (mainline < 0 || mainline > (int) git_commit_parentcount(commit) - 1)
				croak_usage("'mainline' out of range, should be between 0 and %d",
					(int) parents - 1);

			opts.mainline = (unsigned int) mainline;
		}

		repo = GIT_SV_TO_PTR(Repository, self);
		rc = git_revert(
			repo -> repository,
			commit,
			&opts
		);
		git_check_error(rc);

SV *
state(self)
	Repository self

	PREINIT:
		int rc;
		const char *s = NULL;

	CODE:
		rc = git_repository_state(self -> repository);

		switch (rc) {
			case GIT_REPOSITORY_STATE_NONE:
				s = "none";
				break;

			case GIT_REPOSITORY_STATE_MERGE:
				s = "merge";
				break;

			case GIT_REPOSITORY_STATE_REVERT:
				s = "revert";
				break;

			case GIT_REPOSITORY_STATE_CHERRYPICK:
				s = "cherry_pick";
				break;

			case GIT_REPOSITORY_STATE_BISECT:
				s = "bisect";
				break;

			case GIT_REPOSITORY_STATE_REBASE:
				s = "rebase";
				break;

			case GIT_REPOSITORY_STATE_REBASE_INTERACTIVE:
				s = "rebase_interactive";
				break;

			case GIT_REPOSITORY_STATE_REBASE_MERGE:
				s = "rebase_merge";
				break;

			case GIT_REPOSITORY_STATE_APPLY_MAILBOX:
				s = "apply_mailbox";
				break;

			case GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE:
				s = "mailbox_or_rebase";
				break;

			default:
				croak_assert("Unknown state: %i", rc);
		}

		RETVAL = newSVpv(s, 0);

	OUTPUT: RETVAL

void
state_cleanup(self)
	Repository self

	PREINIT:
		int rc;

	CODE:
		rc = git_repository_state_cleanup(self -> repository);
		git_check_error(rc);

SV *
message(self)
	Repository self

	PREINIT:
		int rc;

		git_buf buf = GIT_BUF_INIT_CONST(NULL, 0);

	CODE:
		RETVAL = &PL_sv_undef;

		rc = git_repository_message(&buf, self -> repository);
		if (rc == GIT_OK)
			RETVAL = newSVpv(buf.ptr, 0);

		git_buf_free(&buf);
		git_check_error(rc);

	OUTPUT: RETVAL

SV *
is_bare(self)
	Repository self

	CODE:
		RETVAL = newSViv(git_repository_is_bare(self -> repository));

	OUTPUT: RETVAL

SV *
is_empty(self)
	Repository self

	CODE:
		RETVAL = newSViv(git_repository_is_empty(self -> repository));

	OUTPUT: RETVAL

SV *
is_shallow(self)
	Repository self

	CODE:
		RETVAL = newSViv(git_repository_is_shallow(self -> repository));

	OUTPUT: RETVAL

SV *
is_head_detached(self)
	Repository self

	CODE:
		RETVAL = newSViv(git_repository_head_detached(self -> repository));

	OUTPUT: RETVAL

void
DESTROY(self)
	Repository self

	CODE:
		if (self -> owned)
			git_repository_free(self -> repository);
		Safefree(self);
