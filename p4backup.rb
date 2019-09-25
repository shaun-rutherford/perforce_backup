#!/usr/bin/env ruby

# REQUIREMENTS
  require 'open3'
  require 'time'
  require 'logger'
  require 'digest/md5'
  require 'zlib'
  require 'socket'

# LOCAL VARIABLES
  time                 = Time.new
  time1                = Time.now - (3600 * 24)
  date                 = time.strftime("%Y-%m-%d")
  yesterday            = time1.strftime("%Y-%m-%d")
  changelist_today     = time.strftime("%Y/%m/%d")
  changelist_yesterday = time1.strftime("%Y/%m/%d")
  log_file             = "/var/log/perforce/perforce_backup.log"
  hostname             = Socket.gethostname

# BACKUP BASE, CHECKPOINT AND JOURNAL DIRECTORIES
  @p4d_base_backup_directory                  = "/srv/perforce_backups"
  @p4d_base_journal_backup_directory          = "#{@p4d_base_backup_directory}/journals"
  @p4d_base_checkpoint_backup_directory       = "#{@p4d_base_backup_directory}/checkpoints"
  
  @p4d_journal_backup_file                    = "journal-#{date}"
  @p4d_journal_backup_directory               = "#{@p4d_base_journal_backup_directory}/#{hostname}"
  @p4d_journal_backup_full_path               = "#{@p4d_journal_backup_directory}/#{@p4d_journal_backup_file}"
  @p4d_journal_backup_full_path_compressed    = "#{@p4d_journal_backup_full_path}.jnl.*.gz"

  @p4d_checkpoint_backup_file                 = "checkpoint-#{date}"
  @p4d_checkpoint_backup_file_yesterday       = "checkpoint-#{yesterday}"
  @p4d_checkpoint_backup_directroy            = "#{@p4d_base_checkpoint_backup_directory}/#{hostname}"
  @p4d_checkpoint_backup_full_path            = "#{@p4d_checkpoint_backup_directroy}/#{@p4d_checkpoint_backup_file}"
  @p4d_checkpoint_backup_full_path_compressed = "#{@p4d_checkpoint_backup_full_path}.gz"
  @p4d_checkpoint_backup_full_path_md5        = "#{@p4d_checkpoint_backup_full_path}.md5"
  @p4d_checkpoint_backup_full_path_yesterday_compressed = "#{@p4d_checkpoint_backup_directroy}/#{@p4d_checkpoint_backup_file_yesterday}.gz"

  @p4d_database_live_backup_directory   = "#{@p4d_base_backup_directory}/offline_database"
  @p4d_database_live_backup_full_path   = "#{@p4d_database_live_backup_directory}/db.*"

# OTHER PERFORCE LOCATIONS, FILES AND VARIABLES
  @p4d_root_directory                   = "/srv/perforce"
  @p4d_log_directory                    = "/var/log/perforce"
  @p4d_journal_full_path                = "#{@p4d_log_directory}/journal"
  @p4d_bin                              = "/usr/sbin/p4d"
  @perforce_p4d_arguments               = ""

# CHECKPOINT_RESTORE VARIABLE, CHECK IF WE ARE USING CASE INSENSATIVE
  if "#{@perforce_p4d_arguments}".include?("-C1")
    @p4d_checkpoint_restore = "#{@p4d_bin} -r #{@p4d_database_live_backup_directory} -C1 -z -jr #{@p4d_checkpoint_backup_full_path_compressed}"
  else
    @p4d_checkpoint_restore = "#{@p4d_bin} -r #{@p4d_database_live_backup_directory} -z -jr #{@p4d_checkpoint_backup_full_path_compressed}"
  end

# COMMAND VARIABLES
  @p4d_journal_rotate  = "#{@p4d_bin} -r #{@p4d_root_directory} -J #{@p4d_journal_full_path} -z -jj #{@p4d_journal_backup_full_path}"
  @p4d_journal_restore = "#{@p4d_bin} -r #{@p4d_database_live_backup_directory} -z -f -jr "

  @p4d_checkpoint      = "#{@p4d_bin} -r #{@p4d_database_live_backup_directory} -z -jd #{@p4d_checkpoint_backup_full_path}"

  @p4d_changelist_comparrison = "/usr/local/bin/p4_changes.sh"

# BACKUP DIRECTORY ARRAY
  directory_list = [
                    "#{@p4d_base_backup_directory}",
                    "#{@p4d_base_journal_backup_directory}", 
                    "#{@p4d_base_checkpoint_backup_directory}",
                    "#{@p4d_journal_backup_directory}",
                    "#{@p4d_checkpoint_backup_directroy}"
                   ]

# CREATE PERFORCE LOGFILE DIRECTORY
  Dir.mkdir("#{@p4d_log_directory}") unless File.directory?("#{@p4d_log_directory}")

# DEFINE LOGGER FOR LOGGING MESSAGES
  @log = Logger.new("#{log_file}")
  @log.progname = "p4backup"
  @log.level = Logger::INFO

# METHOD FOR EXECUTING A SHELL COMMAND AND LOGGING ERRORS
  def execute(cmd)
    begin
      Open3.popen3("#{cmd}") do |stdin, stdout, stderr|
        error_log = stderr.read.gsub!("\n", ' ')
        info_log  = stdout.read.gsub!("\n", ' ')
        
        unless info_log.nil?
          @log.info("#{info_log}")
          @return_value = 0
        end

        unless error_log.nil?
          @log.error("#{error_log}")
          @return_value = 1
        end
      end
    end
  end

# VALIDATE JOURNAL AND CHECKPOINT DIRECTORIES EXIST AND IF NOT CREATE THEM FOR US
  directory_list.each do |list|
    begin
      Dir.mkdir("#{list}") unless File.directory?("#{list}")
    rescue
      @log.fatal("#{list} could not be created automatically,  If using NFS share please setup before running again.")
      exit 1
    end
  end

# ROTATE THE LIVE JOURNAL
  execute(@p4d_journal_rotate)
  if @return_value == 1
    @log.fatal("Live journal could not be rotated")
    exit 1
  end

# LIST ALL JOURNAL FILES IN THE BACKUP JOURNAL DIRECTORY AND RESTORE EACH TO THE BACKUP DATABASE IN ORDER
  if Dir["#{@p4d_database_live_backup_directory}/*"].empty?
    @log.fatal("Database Live Backup directory empty, please restore last checkpoint manually")
    exit 1
  else
    perforce_journal_number = []
    Dir["#{@p4d_journal_backup_full_path_compressed}"].sort.each do |file|
      begin
        file_name_split = file.split('.')
        perforce_journal_number << file_name_split[5].to_i
      rescue
        @log.fatal("#{file} couldn't be split for journal restore rotation")
        exit 1
      end
    end
  
    @log.info("Starting restore of Journals")
    perforce_journal_number.sort.each do |journal_number|
        journal_restore = "#{@p4d_journal_restore} #{@p4d_journal_backup_full_path}.jnl.#{journal_number}.gz"
        execute(journal_restore)
    end
  end

# CHECKPOINT THE BACKUP DATABASE
  execute(@p4d_checkpoint)
  if @return_value == 1
    @log.fatal("Checkpoint of Offline Database Failed")
    exit 1
  end

=begin
VALIDATE CHECKPOINT FROM YESTERDAY ISN'T DRAMATICALLY LARGER THEN TODAY'S.
WE HAD ISSUES IN THE PAST WITH PERFORCE STILL ROLLING IN NEW JOURNALS TO THE DATABASE EVEN THOUGH THE DATABASE WAS BAD
THE BACKUP PARITION HAD MAXED OUT HALF WAY THROUGH A CHECKPOINT AND SAID CHECKPOINT WAS RESTORED TO THE OFFLINEDB (WHICH WORKED ODDLY ENOUGH)
=end
  if File.file?("#{@p4d_checkpoint_backup_full_path_compressed}")
    if File.file?("#{@p4d_checkpoint_backup_full_path_yesterday_compressed}")
      if File.size?("#{@p4d_checkpoint_backup_full_path_yesterday_compressed}").to_f / File.size?("#{@p4d_checkpoint_backup_full_path_compressed}").to_f > 1.20
          @log.error("Yesterdays checkpoint is larger then today's checkpoint, this is usually not normal")
      end
    else
      @log.error("Yesterday's checkpoint, #{@p4d_checkpoint_backup_full_path_yesterday_compressed} can't be found")
    end
  else
    @log.fatal("Today's checkpoint, #{@p4d_checkpoint_backup_full_path_compressed} can't be found!")
    exit 1
  end

# CHECK OFFLINE AND ONLINE DB VARIABLE VALUES AREN'T THE SAME SO WE DON'T NUKE THE ONLINE DATABASE
  if "#{@p4d_database_live_backup_directory}" == "#{@p4d_root_directory}"
      @log.fatal("The offline and online database variables are equal, we don't want to nuke the live database")
      exit 1
  end

# MD5 CHECKSUM TODAY'S CHECKPOINT BEFORE ATTEMPTING TO RESTORE
  Zlib::GzipReader.open("#{@p4d_checkpoint_backup_full_path_compressed}") do |gz|
    md5sum_compressed_read =  Digest::MD5.hexdigest gz.read
    md5sum_compressed = md5sum_compressed_read.downcase

    md5sum_file_read = File.read("#{@p4d_checkpoint_backup_full_path_md5}")
    md5sum_file = md5sum_file_read.split[3].downcase

    if md5sum_file == md5sum_compressed
      @log.info("md5 checksum is good, #{md5sum_file} and #{md5sum_compressed} are equal")
    else
      @log.fatal("md5 checksum not equal, checksum file #{md5sum_file}, checkpoint file #{md5sum_compressed}")
      exit 1
    end
  end

# DELETE DATABASE_LIVE_BACKUP DB FILES BEFORE RESTORING CHECKPOINT
  Dir["#{@p4d_database_live_backup_full_path}"].each do |file|
    begin
      @log.info("Deleted #{file} from offline database")
      File.delete(file)
    rescue
      @log.fatal("#{file} could not be deleted for checkpoint restore")
      exit 1
    end
  end

# RESTORE CHECKPOINT TO DATABASE_LIVE_BACKUP
  @log.info("Running #{@p4d_checkpoint_restore}")
  execute(@p4d_checkpoint_restore)
  if @return_value == 1
    @log.fatal("Restore of #{@p4d_checkpoint_backup_full_path_compressed} failed!")
    exit 1
  end

# CHANGELIST COMPARRISON TEST BETWEEN LIVE AND OFFLINEDB
  execute(@p4d_changelist_comparrison)
  if @return_value == 1
    @log.fatal("Changelist comparrison for #{@p4d_root_directory} and #{@p4d_database_live_backup_directory} failed!")
    exit 1
  end
