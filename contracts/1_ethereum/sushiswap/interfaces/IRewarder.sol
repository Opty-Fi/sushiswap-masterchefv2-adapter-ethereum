// SPDX-License-Identifier: MIT
pragma solidity =0.8.11;

interface IRewarder {
    struct PoolInfo {
        uint128 accToken1PerShare;
        uint64 lastRewardTime;
    }

    event LogInit(address indexed rewardToken, address owner, uint256 rewardPerSecond, address indexed masterLpToken);
    event LogOnReward(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event LogRewardPerSecond(uint256 rewardPerSecond);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardTime, uint256 lpSupply, uint256 accToken1PerShare);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function MASTERCHEF_V2() external view returns (address); // solhint-disable-line func-name-mixedcase

    function claimOwnership() external;

    function init(bytes memory data) external payable;

    function masterLpToken() external view returns (address);

    function onSushiReward(
        uint256 pid,
        address _user,
        address to,
        uint256,
        uint256 lpTokenAmount
    ) external;

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function pendingToken(uint256 _pid, address _user) external view returns (uint256 pending);

    function pendingTokens(
        uint256 pid,
        address user,
        uint256
    ) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);

    function poolInfo(uint256) external view returns (uint128 accToken1PerShare, uint64 lastRewardTime);

    function reclaimTokens(
        address token,
        uint256 amount,
        address to
    ) external;

    function rewardPerSecond() external view returns (uint256);

    function rewardRates() external view returns (uint256[] memory);

    function rewardToken() external view returns (address);

    function setRewardPerSecond(uint256 _rewardPerSecond) external;

    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) external;

    function updatePool(uint256 pid) external returns (PoolInfo memory pool);

    function userInfo(uint256, address)
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 unpaidRewards
        );
}
