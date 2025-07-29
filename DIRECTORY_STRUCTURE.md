# SatPi Directory Structure

## Clean Separation: Distribution vs User Data

### 📦 `~/satpi/` - Distribution Code (Version Controlled)

**Purpose**: Contains all code, scripts, services, and configuration files that are part of the SatPi distribution.

**Contents**:
- **Scripts**: All `.sh` shell scripts for satellite operations
- **Python**: All `.py` Python scripts for data processing and uploading  
- **Services**: All `.service` systemd service definitions
- **Configuration**: JSON config files, systemd configs
- **Documentation**: README, setup guides, documentation

**Characteristics**:
- ✅ Version controlled with git
- ✅ Can be synced between machines
- ✅ Contains no user-generated data
- ✅ Safe to backup/restore completely
- ✅ All paths reference this directory in services

### 📁 `~/sat-data/` - User Generated Data (Runtime Only)

**Purpose**: Contains all runtime-generated data from satellite operations.

**Contents**:
- **Raw captures**: `*.raw` files from RTL-SDR
- **Processed data**: `processed/` directory with SatDump output
- **Images**: `images/` directory with generated satellite images  
- **Logs**: Runtime logs from various services
- **Reports**: Analysis and status reports

**Characteristics**:
- ❌ NOT version controlled
- ❌ Contains large binary files  
- ✅ Can be cleaned/purged without affecting system
- ✅ Automatically managed by cleanup scripts
- ✅ Pure user data - no distribution code

## Current Status

### Distribution Sync
- ✅ Mac satpi/ ↔ Pi satpi/ synchronized
- ✅ All services reference ~/satpi/ paths
- ✅ Clean separation maintained

### Data Management  
- ✅ sat-data/ contains only user-generated content
- ✅ 13GB of runtime data properly organized
- ✅ Automated cleanup configured
- ✅ No distribution files in sat-data/

## Benefits

1. **Clean Deployment**: Can sync entire satpi/ directory without touching user data
2. **Safe Updates**: Distribution updates won't affect captured data
3. **Easy Backup**: Can backup code separately from large data files
4. **Clear Ownership**: No confusion about what's distribution vs user content
5. **Automated Maintenance**: Data directory can be cleaned automatically

## Usage

- **Deploy updates**: `rsync satpi/ to target`
- **Clean user data**: Run cleanup scripts on sat-data/ only
- **Backup code**: Version control satpi/ directory
- **Backup data**: Separate backup strategy for sat-data/