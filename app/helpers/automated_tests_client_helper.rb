
module AutomatedTestsClientHelper
  # This is the waiting list for automated testing on the test client. Once a test is requested, it is enqueued
  # and it is waiting for the submission files to be copied in the test location. Resque manages this queue.
  @queue = MarkusConfigurator.markus_ate_files_queue_name

  def fetch_latest_tokens_for_grouping(grouping)
    if grouping.token.nil?
      grouping.create_token(remaining: nil, last_used: nil)
    end
    grouping.token.reassign_tokens
    grouping.token
  end

  def create_test_repo(assignment)
    # Create the automated test repository
    unless File.exist?(MarkusConfigurator
                           .markus_ate_client_dir)
      FileUtils.mkdir(MarkusConfigurator
                          .markus_ate_client_dir)
    end

    test_dir = File.join(MarkusConfigurator
                             .markus_ate_client_dir,
                         assignment.short_identifier)
    unless File.exist?(test_dir)
      FileUtils.mkdir(test_dir)
    end
  end

  # Process Testing Framework form
  # - Process new and updated test files (additional validation to be done at the model level)
  def process_test_form(assignment, params, assignment_params,
                        new_script, new_support_file)
    updated_script_files = {}
    updated_support_files = {}

    testscripts = assignment_params[:test_scripts_attributes] || []
    testsupporters = assignment_params[:test_support_files_attributes] || []

    # Create/Update test scripts
    testscripts.each do |file_num, file|
      # If no new_script then form is empty and skip
      next if testscripts[file_num][:seq_num].empty? && new_script.nil?
      if testscripts[file_num][:script_name].nil?
        # Create new test script file if one with the same name does not exist
        updated_script_files[file_num] = {}
        filename = new_script.original_filename
        if TestScript.exists?(script_name: filename, assignment: assignment)
          raise I18n.t('automated_tests.duplicate_filename') + filename
        end
        updated_script_files[file_num] = file.clone
        # Override filename from form
        updated_script_files[file_num][:script_name] = filename
        updated_script_files[file_num][:seq_num] = file_num
      else
        # Edit existing test script file
        if params[('new_update_script_' + testscripts[file_num][:script_name]).to_sym].nil?
          updated_script_files[file_num] = file.clone
        else
          new_update_script = params[('new_update_script_' + testscripts[file_num][:script_name]).to_sym]
          new_script_name = new_update_script.original_filename
          old_script_name = file[:script_name]
          if TestScript.exists?(script_name: new_script_name, assignment: assignment)
            raise I18n.t('automated_tests.duplicate_filename') + new_script_name
          end
          updated_script_files[file_num] = file.clone
          updated_script_files[file_num][:script_name] = new_script_name
          updated_script_files[file_num][:seq_num] = file_num

          # Uploading new script
          assignment_tests_path = File.join(
                    MarkusConfigurator.markus_ate_client_dir,
                    @assignment.repository_folder,
                    new_script_name)
          # Replace bad line endings from windows
          contents = new_update_script.read.tr("\r", '')
          File.open(assignment_tests_path, 'w') { |f| f.write contents }

          # Deleting old script
          old_script_path = File.join(
            MarkusConfigurator.markus_ate_client_dir,
            @assignment.repository_folder,
            old_script_name)
          if File.exist?(old_script_path)
            File.delete(old_script_path)
          end
        end
      end
      # Always make sure the criterion type is correct.
      # The :criterion_id parameter contains a list of the form
      # [criterion_id, criterion_type], which JSON.parse cannot parse unless
      # neither element is nil
      if testscripts[file_num][:criterion_id].nil? || testscripts[file_num][:criterion_id][0].nil? || testscripts[file_num][:criterion_id][1].nil?
        updated_script_files[file_num][:criterion_type]
      else
        crit_id, crit_type = JSON.parse testscripts[file_num][:criterion_id]
        updated_script_files[file_num][:criterion_id] = crit_id
        updated_script_files[file_num][:criterion_type] = crit_type
      end
    end

    # Create/Update test support files
    # Ignore editing files for now
    testsupporters.each do |file_num, file|
      # Empty file submission, skip
      next if testsupporters[file_num][:file_name].nil? && new_support_file.nil?
      if testsupporters[file_num][:file_name].nil?
        # Create test support file if one with the same name does not exist
        updated_support_files[file_num] = {}
        filename = new_support_file.original_filename
        if TestSupportFile.exists?(file_name: filename, assignment: assignment)
          raise I18n.t('automated_tests.duplicate_filename') + filename
        end
        updated_support_files[file_num] = file.clone
        # Override filename from form
        updated_support_files[file_num][:file_name] = filename
      else
        # Edit existing test support file
        if params[('new_update_file_' + testsupporters[file_num][:file_name]).to_sym].nil?
          updated_support_files[file_num] = file.clone
        else
          new_update_file = params[('new_update_file_' + testsupporters[file_num][:file_name]).to_sym]
          new_file_name = new_update_file.original_filename
          old_file_name = file[:file_name]
          if TestSupportFile.exists?(file_name: new_file_name, assignment: assignment)
            raise I18n.t('automated_tests.duplicate_filename') + new_file_name
          end
          updated_support_files[file_num] = file.clone
          updated_support_files[file_num][:file_name] = new_file_name

          # Uploading new file
          assignment_tests_path = File.join(
                   MarkusConfigurator.markus_ate_client_dir,
                   @assignment.repository_folder,
                   new_file_name)
          File.open(
              assignment_tests_path, 'w') { |f| f.write new_update_file.read }

          # Deleting old file
          old_file_path = File.join(
                    MarkusConfigurator.markus_ate_client_dir,
                    @assignment.repository_folder,
                    old_file_name)
          if File.exist?(old_file_path)
            File.delete(old_file_path)
          end
        end
      end
    end

    # Update test file attributes
    assignment.test_scripts_attributes = updated_script_files
    assignment.test_support_files_attributes = updated_support_files

    assignment.enable_test = assignment_params[:enable_test]
    assignment.enable_student_tests = assignment_params[:enable_student_tests]
    assignment.non_regenerating_tokens = assignment_params[:non_regenerating_tokens]
    assignment.unlimited_tokens = assignment_params[:unlimited_tokens]
    assignment.token_start_date = assignment_params[:token_start_date]
    assignment.token_period = assignment_params[:token_period]
    assignment.tokens_per_period = assignment_params[:tokens_per_period].nil? ?
        0 : assignment_params[:tokens_per_period]

    return assignment
  end

  # Export group repository for testing. Students' submitted files
  # are stored in the group repository. They must be exported
  # before copying to the test server.
  def self.export_group_repo(group, repo_dir, submission = nil)

    # Create the automated test repository
    unless File.exists?(MarkusConfigurator.markus_ate_client_dir)
      FileUtils.mkdir(MarkusConfigurator.markus_ate_client_dir)
    end
    # Delete student's assignment repository if it already exists
    # TODO clean up in client worker, or try to optimize if revision is the same?
    if File.exists?(repo_dir)
      FileUtils.rm_rf(repo_dir)
    end
    # Export the correct repo revision
    if submission.nil?
      group.repo.export(repo_dir)
    else
      files = submission.submission_files
      FileUtils.mkdir(repo_dir)
      files.each do |file|
        file_content = file.retrieve_file
        FileUtils.mkdir_p(File.join(repo_dir, file.path))
        File.open(File.join(repo_dir, file.path, file.filename), 'wb') do |f| # binary write to avoid encoding issues
          f.write(file_content)
        end
      end
    end
  end

  def self.get_test_server_user
    test_server_host = MarkusConfigurator.markus_ate_server_host
    test_server_user = User.find_by(user_name: test_server_host)
    if test_server_user.nil? || !test_server_user.test_server?
      raise I18n.t('automated_tests.error.no_test_server_user', {hostname: test_server_host})
    end
    test_server_user.set_api_key

    return test_server_user
  end

  # Verify the user has the permission to run the tests - admins
  # always have the permission, while student has to
  # belong to the group, and have at least one token.
  def self.check_user_permission(user, grouping, assignment)

    if user.admin?
      return
    end
    if user.ta?
      raise I18n.t('automated_tests.error.ta_not_allowed')
    end
    # Make sure student belongs to this group
    unless user.accepted_groupings.include?(grouping)
      raise I18n.t('automated_tests.error.not_belong_to_group')
    end
    # can skip checking tokens if we have unlimited
    if assignment.unlimited_tokens
      return
    end
    t = grouping.token
    if t.nil? || t.remaining <= 0
      raise I18n.t('automated_tests.error.no_tokens')
    end
    t.decrease_tokens
  end

  # Verify that MarkUs has test scripts to run the test and get them.
  def self.get_test_scripts(assignment, user)

    # No test directory or test files
    test_dir = File.join(MarkusConfigurator.markus_ate_client_dir, assignment.short_identifier)
    unless File.exist?(test_dir)
      raise I18n.t('automated_tests.error.no_test_files')
    end
    all_scripts = TestScript.where(assignment_id: assignment.id)
    if all_scripts.empty?
      raise I18n.t('automated_tests.error.no_test_files')
    end

    # Select a subset of test scripts
    if user.admin?
      test_scripts = all_scripts.select(&:run_by_instructors)
    elsif user.student?
      test_scripts = all_scripts.select(&:run_by_students)
    else
      test_scripts = []
    end
    if test_scripts.empty?
      raise I18n.t('automated_tests.error.no_test_files')
    end

    return test_scripts.sort_by(&:seq_num)
  end

  def self.request_a_test_run(host_with_port, grouping_id, current_user, submission_id = nil)

    grouping = Grouping.find(grouping_id)
    assignment = grouping.assignment
    unless assignment.enable_test
      raise I18n.t('automated_tests.error.not_enabled')
    end
    test_server_user = get_test_server_user
    check_user_permission(current_user, grouping, assignment)

    # if current_user is an instructor, then a submission exists and we use that repo revision
    # if current_user is a student, then we use the latest repo revision
    test_scripts = get_test_scripts(assignment, current_user)
    test_scripts.map! do |script|
      script.script_name
    end
    group = grouping.group
    repo_dir = File.join(MarkusConfigurator.markus_ate_client_dir, group.repo_name)
    submission = submission_id.nil? ? nil : Submission.find(submission_id)
    export_group_repo(group, repo_dir, submission)
    Resque.enqueue(AutomatedTestsClientHelper, host_with_port, test_scripts, current_user.api_key,
                   test_server_user.api_key, grouping_id, submission_id)
  end

  # Verify that MarkUs has student files to run the test.
  # Note: this does not guarantee all required files are presented.
  # Instead, it checks if there is at least one source file is successfully exported.
  def self.repo_files_available?(assignment, repo_dir)
    # No assignment directory or no files in repo (only current and parent directory pointers)
    assignment_dir = File.join(repo_dir, assignment.repository_folder)
    if !File.exist?(assignment_dir) || Dir.entries(assignment_dir).length <= 2
      return false
    end

    return true
  end

  def self.create_test_script_result(script_name, assignment, grouping, submission)
    revision_number = submission.nil? ?
        grouping.group.repo.get_latest_revision.revision_number :
        submission.revision_number
    submission_id = submission.nil? ? nil : submission.id
    test_script = TestScript.find_by(assignment_id: assignment.id, script_name: script_name)

    return grouping.test_script_results.create(
        test_script_id: test_script.id,
        submission_id: submission_id,
        marks_earned: 0,
        repo_revision: revision_number)
  end

  def self.create_all_test_scripts_error_result(test_scripts, assignment, grouping, submission, result_name, result_message)
    test_scripts.each do |script_name|
      test_script_result = create_test_script_result(script_name, assignment, grouping, submission)
      add_test_error_result(test_script_result, result_name, result_message)
      test_script_result.save
    end
    unless submission.nil?
      submission.set_marks_for_tests
    end
  end

  def self.add_test_result(test_script_result, name, input, actual, expected, marks_earned, status)
    test_script_result.test_results.create(
        name: name,
        input: CGI.unescapeHTML(input),
        actual_output: CGI.unescapeHTML(actual),
        expected_output: CGI.unescapeHTML(expected),
        marks_earned: marks_earned,
        completion_status: status)
  end

  def self.add_test_error_result(test_script_result, result_name, result_message)
    add_test_result(test_script_result, result_name, '', result_message, '', 0, 'error')
  end

  # Perform a job for automated testing. This code is run by
  # the Resque workers - it should not be called from other functions.
  def self.perform(host_with_port, test_scripts, user_api_key, server_api_key, grouping_id, submission_id)

    grouping = Grouping.find(grouping_id)
    assignment = grouping.assignment
    group = grouping.group

    # create empty test results for no submission files
    repo_dir = File.join(MarkusConfigurator.markus_ate_client_dir, group.repo_name)
    unless repo_files_available?(assignment, repo_dir)
      submission = submission_id.nil? ? nil : Submission.find(submission_id)
      create_all_test_scripts_error_result(test_scripts, assignment, grouping, submission,
                                           I18n.t('automated_tests.test_result.all_tests'),
                                           I18n.t('automated_tests.test_result.no_source_files'))
      return
    end

    submission_path = File.join(repo_dir, assignment.repository_folder)
    assignment_tests_path = File.join(MarkusConfigurator.markus_ate_client_dir, assignment.repository_folder)
    markus_address = Rails.application.config.action_controller.relative_url_root.nil? ?
        host_with_port :
        host_with_port + Rails.application.config.action_controller.relative_url_root
    test_server_host = MarkusConfigurator.markus_ate_server_host
    test_server_user = User.find_by(user_name: test_server_host)
    if test_server_user.nil?
      return
    end
    files_path = MarkusConfigurator.markus_ate_server_files_dir
    tests_path = MarkusConfigurator.markus_ate_server_tests_dir
    same_path = (MarkusConfigurator.markus_ate_server_files_dir == MarkusConfigurator.markus_ate_server_tests_dir)
    results_path = MarkusConfigurator.markus_ate_server_results_dir
    test_username = (test_server_host == 'localhost' || MarkusConfigurator.markus_ate_server_files_username ==
                                                        MarkusConfigurator.markus_ate_server_tests_username) ?
        nil : MarkusConfigurator.markus_ate_server_tests_username
    server_queue = "queue:#{MarkusConfigurator.markus_ate_tests_queue_name}"
    resque_params = {:class => 'AutomatedTestsServer',
                     :args => [markus_address, user_api_key, server_api_key, test_username, test_scripts,
                               'files_path_placeholder', tests_path, results_path, assignment.id, group.id,
                               submission_id]}

    begin
      if test_server_host == 'localhost'
        # tests executed locally with no authentication:
        # create a temp folder, copying the student's submission and all necessary test files
        FileUtils.mkdir_p(files_path, {mode: 0700}) # create base files dir if not already existing..
        files_path = Dir.mktmpdir(nil, files_path) # ..then create temp subfolder
        FileUtils.cp_r("#{submission_path}/.", files_path) # == cp -r '#{submission_path}'/* '#{files_path}'
        FileUtils.cp_r("#{assignment_tests_path}/.", files_path) # == cp -r '#{assignment_tests_path}'/* '#{files_path}'
        # enqueue locally using redis api
        resque_params[:args][5] = files_path
        if same_path
          resque_params[:args][6] = files_path
        end
        Resque.redis.rpush(server_queue, JSON.generate(resque_params))
      else
        # tests executed locally or remotely with authentication:
        # copy the student's submission and all necessary files through ssh in a temp folder
        file_username = MarkusConfigurator.markus_ate_server_files_username
        Net::SSH::start(test_server_host, file_username, auth_methods: ['publickey']) do |ssh|
          ssh.exec!("mkdir -m 700 -p '#{files_path}'") # create base tests dir if not already existing..
          files_path = ssh.exec!("mktemp -d --tmpdir='#{files_path}'").strip # ..then create temp subfolder
          Dir.foreach(submission_path) do |file_name| # workaround scp gem not supporting wildcard *
            next if file_name == '.' or file_name == '..'
            file_path = File.join(submission_path, file_name)
            options = File.directory?(file_path) ? {:recursive => true} : {}
            ssh.scp.upload!(file_path, files_path, options)
          end
          Dir.foreach(assignment_tests_path) do |file_name| # workaround scp gem not supporting wildcard *
            next if file_name == '.' or file_name == '..'
            file_path = File.join(assignment_tests_path, file_name)
            ssh.scp.upload!(file_path, files_path)
          end
          # enqueue remotely directly with redis-cli, resque does not allow for multiple redis servers
          resque_params[:args][5] = files_path
          if same_path
            resque_params[:args][6] = files_path
          end
          ssh.exec!("redis-cli rpush \"resque:#{server_queue}\" '#{JSON.generate(resque_params)}'")
        end
      end
    rescue Exception => e
      submission = submission_id.nil? ? nil : Submission.find(submission_id)
      create_all_test_scripts_error_result(test_scripts, assignment, grouping, submission,
                                           I18n.t('automated_tests.test_result.all_tests'),
                                           I18n.t('automated_tests.test_result.bad_server',
                                                  {hostname: test_server_host, error: e.message}))
    end
  end

  def self.process_test_result(raw_result, test_scripts_ran, assignment, grouping, submission)

    # check that results are somewhat well-formed xml at the top level (i.e. they don't crash the parser)
    result = nil
    begin
      result = Hash.from_xml(raw_result)
    rescue => e
      create_all_test_scripts_error_result(test_scripts_ran, assignment, grouping, submission,
                                           I18n.t('automated_tests.test_result.all_tests'),
                                           I18n.t('automated_tests.test_result.bad_results', {xml: e.message}))
      unless submission.nil?
        submission.set_marks_for_tests
      end
      return
    end
    test_run = result['testrun']
    test_scripts = test_run.nil? ? nil : test_run['test_script']
    if test_run.nil? || test_scripts.nil?
      create_all_test_scripts_error_result(test_scripts_ran, assignment, grouping, submission,
                                           I18n.t('automated_tests.test_result.all_tests'),
                                           I18n.t('automated_tests.test_result.bad_results', {xml: result}))
      unless submission.nil?
        submission.set_marks_for_tests
      end
      return
    end

    # process results
    unless test_scripts.is_a?(Array) # Hash.from_xml returns a hash if it's a single test script and an array otherwise
      test_scripts = [test_scripts]
    end
    new_test_script_results = {}
    test_scripts.each do |test_script|
      script_name = test_script['script_name']
      if script_name.nil? # with malformed xml, some test script results could be valid and some won't, recover later
        next
      end
      total_marks = 0
      new_test_script_result = create_test_script_result(script_name, assignment, grouping, submission)
      new_test_script_results[script_name] = new_test_script_result
      tests = test_script['test']
      if tests.nil?
        add_test_error_result(new_test_script_result, I18n.t('automated_tests.test_result.all_tests'),
                              I18n.t('automated_tests.test_result.no_tests'))
        next
      end
      unless tests.is_a?(Array) # same workaround as above, Hash.from_xml returns a hash if it's a single test
        tests = [tests]
      end
      tests.each do |test|
        test_name = test['name']
        if test_name.nil? # with malformed xml, some test results could be valid and some won't
          add_test_error_result(new_test_script_result, I18n.t('automated_tests.test_result.unknown_test'),
                                I18n.t('automated_tests.test_result.bad_results', {xml: test}))
          next
        end
        marks_earned = test['marks_earned'].nil? ? 0 : test['marks_earned'].to_i
        test_input = test['input'].nil? ? '' : test['input']
        test_actual = test['actual'].nil? ? '' : test['actual']
        test_expected = test['expected'].nil? ? '' : test['expected']
        test_status = test['status']
        if test_status.nil? or not test_status.in?(%w(pass fail error))
          test_status = 'error'
          marks_earned = 0
        end
        add_test_result(new_test_script_result, test_name, test_input, test_actual, test_expected, marks_earned,
                        test_status)
        total_marks += marks_earned
      end
      new_test_script_result.marks_earned = total_marks
      new_test_script_result.save!
    end

    # try to recover from malformed xml at the test script level
    test_scripts_ran.each do |script_name|
      if new_test_script_results[script_name].nil?
        new_test_script_result = create_test_script_result(script_name, assignment, grouping, submission)
        add_test_error_result(new_test_script_result, I18n.t('automated_tests.test_result.all_tests'),
                              I18n.t('automated_tests.test_result.bad_results', {xml: result}))
      end
    end

    # set the marks assigned by the test
    unless submission.nil?
      submission.set_marks_for_tests
    end
  end

end
