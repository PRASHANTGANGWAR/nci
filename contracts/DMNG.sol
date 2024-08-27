// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IERC20Extended.sol";

contract NCIContract is ERC20, Ownable {
    using SafeERC20 for IERC20Extended;

    uint8 private customDecimals;
    uint256 public baseTokenPrice;
    uint256 public currentSupply;
    uint256 public softCap;
    uint256 public hardCap; // equal to total supply
    uint256 public investorPool;
    uint256 public profitPool;
    uint256 public campaignStartTime;
    uint256 public campaignEndTime;
    uint256 public totalRaised;
    bool public softCapReached;
    bool public withdrawEnabled;

    IERC20Extended public liquidityTokenContract;

    mapping(address => bool) public admin;

    event TokensPurchased(
        address indexed investor,
        uint256 liquidityTokenAmount,
        uint256 tokenAmount,
        uint256 baseTokenPrice,
        uint256 blockTimestamp
    );
    event ProfitAdded(
        address indexed ownerAdminAddress,
        uint256 amount,
        uint256 blockTimestamp
    );
    event BaseTokenPriceUpdated(uint256 newPrice);
    event WithdrawnInvestor(
        address indexed investor,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount,
        uint256 blockTimestamp
    );
    event WithdrawAdminOwner(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateAdmin(address indexed adminAddress, bool value);
    event AddLiquidity(
        address indexed ownerAdminAddress,
        uint256 tokenAmount,
        uint256 blockTimestamp
    );
    event UpdateWithdrawEnabled(bool value);

    constructor(
        string memory _tokenName,
        string memory _symbol,
        uint256 _initialSupply,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _campaignEndTime,
        uint8 _customDecimals,
        address _liquidityTokenContract,
        address _initialOwner,
        address _admin
    ) Ownable(_initialOwner) ERC20(_tokenName, _symbol) {
        require(
            _campaignEndTime > 0,
            "Campaign duration must be greater than zero"
        );
        require(_softCap < _hardCap, "Soft cap must be less than hard cap");
        
        _mint(address(this), _initialSupply);
        
        currentSupply = _initialSupply;
        softCap = _softCap;
        hardCap = _hardCap;
        
        softCapReached = false;
        liquidityTokenContract = IERC20Extended(_liquidityTokenContract);
        baseTokenPrice =
            5 *
            (10 ** IERC20Extended(_liquidityTokenContract).decimals());
        customDecimals = _customDecimals;
        campaignStartTime = block.number;
        campaignEndTime = _campaignEndTime;
        admin[_admin] = true;
        withdrawEnabled = false;
    }

 
  
    modifier campaignComplete() {
        require(block.number >= campaignEndTime, "Campaign has not been completed");
        _;
    }

    modifier softCapReachedOnly() {
        require(softCapReached, "Soft cap is not reached");
        _;
    }

    modifier hardCapReachedOnly() {
        require(totalRaised < hardCap, "Hard cap reached");
        _;
    }
    modifier onlyAdminOrOwner() {
        require(admin[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier withdrawEnabledOrNot() {
        require(withdrawEnabled, "Currently Withdraw is disabled");
        _;
    }


    modifier onlyDuringCampaign() {
        require(block.number >= campaignStartTime && block.number <= campaignEndTime, "Campaign is not active");
        _;
    }


    // Function to purchase tokens during the campaign
    function buyTokens(
        uint256 _tokenValue
    ) external   {
        require(_tokenValue > 0, "Amount must be greater than zero");

        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _tokenValue &&
                liquidityTokenContract.balanceOf(msg.sender) >= _tokenValue,
            "Insufficient allowance or balance"
        );

        uint256 tokensToPurchase = (_tokenValue * 10 ** customDecimals) /
            baseTokenPrice;

        require(
            balanceOf(address(this)) >= tokensToPurchase,
            "Not enough tokens available"
        );

        liquidityTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            _tokenValue
        );
        investorPool += _tokenValue;
        currentSupply -= tokensToPurchase;
        totalRaised += tokensToPurchase;

        _transfer(address(this), msg.sender, tokensToPurchase);

        if (currentSupply <= totalSupply() - softCap) {
            softCapReached = true;
        }

        emit TokensPurchased(
            msg.sender,
            _tokenValue,
            tokensToPurchase,
            baseTokenPrice,
            block.timestamp
        );
    }

    // Function to sell tokens after the campaign is completed
    function sellTokens(
        uint256 _tokenValue
    ) external softCapReachedOnly campaignComplete {
        _withdraw(_tokenValue);
    }

    // Admin or Owner withdraws funds after the campaign
    function withdrawAdminOwner(
        uint256 _tokenValue
    ) external onlyAdminOrOwner softCapReachedOnly  {
        require(investorPool >= _tokenValue, "Insufficient liquidity in pool");

        liquidityTokenContract.safeTransfer(msg.sender, _tokenValue);
        investorPool -= _tokenValue;

        emit WithdrawAdminOwner(msg.sender, _tokenValue, block.timestamp);
    }

    // Add profits to the contract, updating the base token price
    function addProfit(
        uint256 _profitAmount
    ) external onlyAdminOrOwner softCapReachedOnly {
        require(
            _profitAmount > 0 && currentSupply > 0,
            "Profit amount and current supply must both be greater than zero."
        );
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _profitAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _profitAmount,
            "Insufficient allowance or balance"
        );
        
        liquidityTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            _profitAmount
        );
        profitPool += _profitAmount;

        uint256 newTokenValue = calculateNewTokenValue(_profitAmount);
        baseTokenPrice += newTokenValue;

        emit BaseTokenPriceUpdated(baseTokenPrice);
        emit ProfitAdded(msg.sender, _profitAmount, block.timestamp);
    }

    // Add liquidity to the profit pool
    function addLiquidity(
        uint256 _tokenAmount
    ) external onlyAdminOrOwner softCapReachedOnly campaignComplete {
        require(_tokenAmount > 0, "Amount must be greater than zero.");
        require(
            liquidityTokenContract.allowance(msg.sender, address(this)) >=
                _tokenAmount &&
                liquidityTokenContract.balanceOf(msg.sender) >= _tokenAmount,
            "Insufficient allowance or balance"
        );
        
        liquidityTokenContract.safeTransferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );
        profitPool += _tokenAmount;

        emit AddLiquidity(msg.sender, _tokenAmount, block.timestamp);
    }

    // Withdraw funds for investors
    function withdrawFund(
        uint256 _tokenValue
    ) external withdrawEnabledOrNot {
        _withdraw(_tokenValue);
    }

    // Internal withdraw function
    function _withdraw(
        uint256 _tokenValue
    ) internal {
        require(
            _tokenValue > 0 && balanceOf(msg.sender) >= _tokenValue,
            "Insufficient balance"
        );

        uint256 tokens = (_tokenValue * baseTokenPrice) /
            10 ** liquidityTokenContract.decimals();
        require(profitPool >= tokens, "Pool needs to be balanced to withdraw");

        _transfer(msg.sender, address(this), _tokenValue);

        liquidityTokenContract.safeTransfer(msg.sender, tokens);

        profitPool -= tokens;
        currentSupply += _tokenValue;

        emit WithdrawnInvestor(
            msg.sender,
            _tokenValue,
            tokens,
            block.timestamp
        );
    }

    // Calculate the new token value based on profit added
    function calculateNewTokenValue(
        uint256 _profitAmount
    ) public view returns (uint256) {
        return
            (_profitAmount * 10 ** liquidityTokenContract.decimals()) /
            currentSupply;
    }

    // Override the decimals function to return custom decimals
    function decimals() public view virtual override returns (uint8) {
        return customDecimals;
    }

    // Update admin status
    function updateAdmin(
        address _admin,
        bool _value
    ) external onlyAdminOrOwner {
        require(_admin != address(0), "Admin address cannot be zero address");
        admin[_admin] = _value;
        emit UpdateAdmin(_admin, _value);
    }

   // Update withdraw status
    function updateWithdrawEnabled(
        bool _value
    ) external onlyAdminOrOwner {
        withdrawEnabled = _value;
       emit UpdateWithdrawEnabled(_value);
    }

    function updateCampaignEndTime(uint _campaignEndTime) external  {
        campaignEndTime = _campaignEndTime;
    }
    
}
